\set ON_ERROR_STOP on

BEGIN;
SET LOCAL ROLE eventor_owner;

SELECT set_config('app.organization_id','a4000000-0000-4000-8000-000000000001',true);

INSERT INTO eogp.organizations (id,slug,name,status,default_timezone)
VALUES (
  'a4000000-0000-4000-8000-000000000001',
  'ci-public-inquiry',
  'CI Public Inquiry Organization',
  'active',
  'Europe/Sarajevo'
);

INSERT INTO eogp.booking_form_definitions (
  id,organization_id,scope_kind,form_code,name,status
) VALUES (
  'a5000000-0000-4000-8000-000000000001',
  'a4000000-0000-4000-8000-000000000001',
  'organization',
  'venue-rental',
  'Public venue rental inquiry',
  'active'
);

INSERT INTO eogp.booking_form_revisions (
  id,organization_id,form_definition_id,revision_number,locale,
  field_schema,state,published_at
) VALUES (
  'a6000000-0000-4000-8000-000000000001',
  'a4000000-0000-4000-8000-000000000001',
  'a5000000-0000-4000-8000-000000000001',
  1,
  'bs-BA',
  '{"fields":[{"code":"event_date","type":"date","required":true}]}'::jsonb,
  'published',
  clock_timestamp()
);

DO $test$
DECLARE
  v_first jsonb;
  v_replay jsonb;
  v_conflict jsonb;
  v_unpublished jsonb;
  v_limited jsonb;
  v_result jsonb;
  v_inquiry_id uuid;
  v_public_reference text;
  v_count integer;
  v_ciphertext bytea := decode('45435031' || repeat('00',29),'hex');
  v_source text := repeat('a',64);
  v_key text := repeat('b',64);
  v_request text := repeat('c',64);
  v_key_i text;
  v_request_i text;
  i integer;
BEGIN
  -- A first submission creates one encrypted inquiry and one idempotency record.
  SELECT eogp.submit_public_booking_inquiry(
    'ci-public-inquiry','venue-rental',
    'a6000000-0000-4000-8000-000000000001',
    v_source,v_key,v_request,
    v_ciphertext,v_ciphertext,
    NULL,NULL,NULL,NULL,
    NULL,NULL,'Europe/Sarajevo'
  ) INTO v_first;

  IF v_first->>'status' <> 'received'
     OR v_first->>'replayed' <> 'false'
     OR v_first->>'publicReference' !~ '^INQ-[0-9A-F]{16}$' THEN
    RAISE EXCEPTION 'first public inquiry submission returned an unexpected result: %',v_first;
  END IF;

  v_inquiry_id := (v_first->>'inquiryId')::uuid;
  v_public_reference := v_first->>'publicReference';

  -- Replays return the original inquiry and do not consume another rate-limit slot.
  SELECT eogp.submit_public_booking_inquiry(
    'ci-public-inquiry','venue-rental',
    'a6000000-0000-4000-8000-000000000001',
    v_source,v_key,v_request,
    v_ciphertext,v_ciphertext,
    NULL,NULL,NULL,NULL,
    NULL,NULL,'Europe/Sarajevo'
  ) INTO v_replay;

  IF v_replay->>'replayed' <> 'true'
     OR (v_replay->>'inquiryId')::uuid <> v_inquiry_id
     OR v_replay->>'publicReference' <> v_public_reference THEN
    RAISE EXCEPTION 'idempotent inquiry replay did not return the original result: %',v_replay;
  END IF;

  -- Reusing a key with a different payload is rejected without inserting a second inquiry.
  SELECT eogp.submit_public_booking_inquiry(
    'ci-public-inquiry','venue-rental',
    'a6000000-0000-4000-8000-000000000001',
    v_source,v_key,repeat('d',64),
    v_ciphertext,v_ciphertext,
    NULL,NULL,NULL,NULL,
    NULL,NULL,'Europe/Sarajevo'
  ) INTO v_conflict;

  IF v_conflict->>'idempotencyConflict' <> 'true' THEN
    RAISE EXCEPTION 'idempotency key reuse with a different payload was not rejected: %',v_conflict;
  END IF;

  -- An unpublished or unknown revision cannot create an inquiry or consume a rate slot.
  SELECT eogp.submit_public_booking_inquiry(
    'ci-public-inquiry','venue-rental',
    'a6000000-0000-4000-8000-000000000099',
    v_source,repeat('f',64),repeat('1',64),
    v_ciphertext,v_ciphertext,
    NULL,NULL,NULL,NULL,
    NULL,NULL,'Europe/Sarajevo'
  ) INTO v_unpublished;

  IF v_unpublished->>'formUnavailable' <> 'true' THEN
    RAISE EXCEPTION 'unknown/unpublished form revision was accepted: %',v_unpublished;
  END IF;

  -- Same source fingerprint: ten distinct inquiries are accepted in this UTC hour.
  FOR i IN 2..10 LOOP
    v_key_i := repeat(lpad(to_hex(i),2,'0'),32);
    v_request_i := repeat(lpad(to_hex(i+16),2,'0'),32);
    SELECT eogp.submit_public_booking_inquiry(
      'ci-public-inquiry','venue-rental',
      'a6000000-0000-4000-8000-000000000001',
      v_source,v_key_i,v_request_i,
      v_ciphertext,v_ciphertext,
      NULL,NULL,NULL,NULL,
      NULL,NULL,'Europe/Sarajevo'
    ) INTO v_result;

    IF v_result->>'status' <> 'received'
       OR v_result->>'replayed' <> 'false' THEN
      RAISE EXCEPTION 'submission % was not accepted before the hourly limit: %',i,v_result;
    END IF;
  END LOOP;

  -- The eleventh distinct request from the same source is rate-limited.
  SELECT eogp.submit_public_booking_inquiry(
    'ci-public-inquiry','venue-rental',
    'a6000000-0000-4000-8000-000000000001',
    v_source,repeat('e',64),repeat('f',64),
    v_ciphertext,v_ciphertext,
    NULL,NULL,NULL,NULL,
    NULL,NULL,'Europe/Sarajevo'
  ) INTO v_limited;

  IF v_limited->>'rateLimited' <> 'true'
     OR (v_limited->>'retryAfterSeconds')::integer < 1 THEN
    RAISE EXCEPTION 'eleventh inquiry from the same source was not rate-limited: %',v_limited;
  END IF;

  SELECT count(*) INTO v_count
    FROM eogp.public_booking_submission_rate_limits
   WHERE organization_id='a4000000-0000-4000-8000-000000000001'
     AND source_fingerprint=v_source
     AND window_started_at=date_trunc('hour',clock_timestamp() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';

  IF v_count <> 1 OR NOT EXISTS (
    SELECT 1 FROM eogp.public_booking_submission_rate_limits
     WHERE organization_id='a4000000-0000-4000-8000-000000000001'
       AND source_fingerprint=v_source
       AND request_count=10
  ) THEN
    RAISE EXCEPTION 'hourly source limit was not stored as exactly ten accepted submissions';
  END IF;

  SELECT count(*) INTO v_count
    FROM eogp.booking_inquiries
   WHERE organization_id='a4000000-0000-4000-8000-000000000001';
  IF v_count <> 10 THEN
    RAISE EXCEPTION 'expected ten inquiries after replay/conflict/rate-limit checks, got %',v_count;
  END IF;

  IF has_table_privilege('eventor_runtime','eogp.public_booking_submission_rate_limits','SELECT')
     OR has_table_privilege('eventor_runtime','eogp.public_booking_submission_rate_limits','INSERT')
     OR has_table_privilege('eventor_runtime','eogp.public_booking_submission_idempotency','SELECT')
     OR has_table_privilege('eventor_runtime','eogp.public_booking_submission_idempotency','INSERT') THEN
    RAISE EXCEPTION 'runtime role has direct access to public inquiry rate-limit or idempotency tables';
  END IF;

  IF NOT has_function_privilege(
    'eventor_runtime',
    'eogp.submit_public_booking_inquiry(text,text,uuid,text,text,text,bytea,bytea,text,bytea,text,bytea,timestamptz,timestamptz,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role cannot execute the restricted public inquiry command';
  END IF;
END;
$test$;

ROLLBACK;
