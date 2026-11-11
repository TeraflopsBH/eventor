-- Public booking inquiries are accepted through one narrowly scoped,
-- rate-limited, idempotent database command. Anonymous callers never receive
-- table privileges and no raw source IP or idempotency key is persisted.

CREATE TABLE eogp.public_booking_submission_rate_limits (
    organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    source_fingerprint text NOT NULL
      CHECK (source_fingerprint ~ '^[0-9a-f]{64}$'),
    window_started_at timestamptz NOT NULL,
    request_count integer NOT NULL CHECK (request_count BETWEEN 1 AND 10),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (organization_id, source_fingerprint, window_started_at)
);

CREATE TABLE eogp.public_booking_submission_idempotency (
    organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    key_fingerprint text NOT NULL
      CHECK (key_fingerprint ~ '^[0-9a-f]{64}$'),
    request_fingerprint text NOT NULL
      CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
    inquiry_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (organization_id, key_fingerprint),
    FOREIGN KEY (organization_id, inquiry_id)
      REFERENCES eogp.booking_inquiries(organization_id, id)
);

ALTER TABLE eogp.public_booking_submission_rate_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.public_booking_submission_rate_limits FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation
  ON eogp.public_booking_submission_rate_limits
  USING (organization_id = eogp.current_organization_id())
  WITH CHECK (organization_id = eogp.current_organization_id());

ALTER TABLE eogp.public_booking_submission_idempotency ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.public_booking_submission_idempotency FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation
  ON eogp.public_booking_submission_idempotency
  USING (organization_id = eogp.current_organization_id())
  WITH CHECK (organization_id = eogp.current_organization_id());

REVOKE ALL ON TABLE
  eogp.public_booking_submission_rate_limits,
  eogp.public_booking_submission_idempotency
FROM PUBLIC, eventor_runtime, eventor_worker, eventor_auth;

CREATE FUNCTION eogp.submit_public_booking_inquiry(
  p_organization_slug text,
  p_form_code text,
  p_form_revision_id uuid,
  p_source_fingerprint text,
  p_key_fingerprint text,
  p_request_fingerprint text,
  p_submitted_values_ciphertext bytea,
  p_requester_name_ciphertext bytea,
  p_requester_email_hash text,
  p_requester_email_ciphertext bytea,
  p_requester_phone_hash text,
  p_requester_phone_ciphertext bytea,
  p_requested_start timestamptz,
  p_requested_end timestamptz,
  p_requested_timezone text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_organization_id uuid;
  v_default_timezone text;
  v_timezone text;
  v_window_started_at timestamptz;
  v_now timestamptz;
  v_request_count integer;
  v_inquiry_id uuid;
  v_public_reference text;
  v_status text;
  v_existing eogp.public_booking_submission_idempotency%ROWTYPE;
BEGIN
  IF nullif(trim(p_organization_slug), '') IS NULL
     OR length(p_organization_slug) > 80
     OR nullif(trim(p_form_code), '') IS NULL
     OR length(p_form_code) > 80
     OR p_form_revision_id IS NULL
     OR p_source_fingerprint IS NULL OR p_source_fingerprint !~ '^[0-9a-f]{64}$'
     OR p_key_fingerprint IS NULL OR p_key_fingerprint !~ '^[0-9a-f]{64}$'
     OR p_request_fingerprint IS NULL OR p_request_fingerprint !~ '^[0-9a-f]{64}$'
     OR p_submitted_values_ciphertext IS NULL
     OR octet_length(p_submitted_values_ciphertext) <= 32
     OR p_requester_name_ciphertext IS NULL
     OR octet_length(p_requester_name_ciphertext) <= 32
     OR ((p_requester_email_hash IS NULL) <> (p_requester_email_ciphertext IS NULL))
     OR ((p_requester_phone_hash IS NULL) <> (p_requester_phone_ciphertext IS NULL))
     OR (p_requester_email_hash IS NOT NULL AND p_requester_email_hash !~ '^[0-9a-f]{64}$')
     OR (p_requester_phone_hash IS NOT NULL AND p_requester_phone_hash !~ '^[0-9a-f]{64}$')
     OR (p_requester_email_ciphertext IS NOT NULL AND octet_length(p_requester_email_ciphertext) <= 32)
     OR (p_requester_phone_ciphertext IS NOT NULL AND octet_length(p_requester_phone_ciphertext) <= 32)
     OR (p_requested_start IS NOT NULL AND p_requested_end IS NOT NULL AND p_requested_end <= p_requested_start) THEN
    RAISE EXCEPTION 'invalid public booking inquiry payload' USING ERRCODE = '22023';
  END IF;

  -- Resolve and lock the active public route before establishing tenant context.
  -- Organization suspension and slug changes serialize against an in-flight submit.
  SELECT organization_id INTO v_organization_id
    FROM eogp.public_organization_routes
   WHERE organization_slug = trim(p_organization_slug)
     AND is_active = true
   FOR SHARE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('formUnavailable', true);
  END IF;

  PERFORM set_config('app.organization_id', v_organization_id::text, true);

  -- Serialize the same key across API instances. The keyed fingerprint, not
  -- the caller's raw Idempotency-Key, is what is persisted.
  PERFORM pg_advisory_xact_lock(
    hashtextextended(v_organization_id::text || ':' || p_key_fingerprint, 0)
  );

  SELECT * INTO v_existing
    FROM eogp.public_booking_submission_idempotency
   WHERE organization_id = v_organization_id
     AND key_fingerprint = p_key_fingerprint
   FOR UPDATE;
  IF FOUND THEN
    IF v_existing.request_fingerprint <> p_request_fingerprint THEN
      RETURN jsonb_build_object('idempotencyConflict', true);
    END IF;

    SELECT public_reference, status
      INTO v_public_reference, v_status
      FROM eogp.booking_inquiries
     WHERE organization_id = v_organization_id
       AND id = v_existing.inquiry_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'idempotency record references a missing inquiry'
        USING ERRCODE = '55000';
    END IF;

    RETURN jsonb_build_object(
      'inquiryId', v_existing.inquiry_id,
      'publicReference', v_public_reference,
      'status', v_status,
      'replayed', true
    );
  END IF;

  -- Accept only a revision of this exact active form. Previously published
  -- revisions remain valid to avoid breaking visitors with an already-open page.
  PERFORM 1
    FROM eogp.booking_form_definitions definition
    JOIN eogp.booking_form_revisions revision
      ON revision.organization_id = definition.organization_id
     AND revision.form_definition_id = definition.id
   WHERE definition.organization_id = v_organization_id
     AND definition.form_code = p_form_code
     AND definition.status = 'active'
     AND revision.id = p_form_revision_id
     AND revision.state = 'published'
     AND revision.published_at IS NOT NULL
   FOR SHARE OF definition, revision;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('formUnavailable', true);
  END IF;

  SELECT default_timezone INTO v_default_timezone
    FROM eogp.organizations
   WHERE id = v_organization_id;
  v_timezone := coalesce(nullif(trim(p_requested_timezone), ''), v_default_timezone);
  IF v_timezone IS NULL OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = v_timezone
  ) THEN
    RAISE EXCEPTION 'invalid requested timezone' USING ERRCODE = '22023';
  END IF;

  -- Durable UTC-hour buckets make the limit consistent across API instances.
  -- Replays and unavailable revisions return before this counter is changed.
  v_now := clock_timestamp();
  v_window_started_at := date_trunc('hour', v_now AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';

  DELETE FROM eogp.public_booking_submission_rate_limits
   WHERE organization_id = v_organization_id
     AND window_started_at < v_window_started_at - interval '48 hours';

  INSERT INTO eogp.public_booking_submission_rate_limits (
    organization_id, source_fingerprint, window_started_at, request_count
  ) VALUES (
    v_organization_id, p_source_fingerprint, v_window_started_at, 1
  )
  ON CONFLICT (organization_id, source_fingerprint, window_started_at)
  DO UPDATE SET request_count = eogp.public_booking_submission_rate_limits.request_count + 1,
                updated_at = clock_timestamp()
  WHERE eogp.public_booking_submission_rate_limits.request_count < 10
  RETURNING request_count INTO v_request_count;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'rateLimited', true,
      'retryAfterSeconds',
        greatest(1, ceil(extract(epoch FROM (v_window_started_at + interval '1 hour' - v_now)))::integer)
    );
  END IF;

  v_public_reference := 'INQ-' ||
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 16));

  INSERT INTO eogp.booking_inquiries (
    organization_id, public_reference, form_revision_id,
    submitted_values_ciphertext, requester_name_ciphertext,
    requester_email_hash, requester_email_ciphertext,
    requester_phone_hash, requester_phone_ciphertext,
    requested_start, requested_end, requested_timezone
  ) VALUES (
    v_organization_id, v_public_reference, p_form_revision_id,
    p_submitted_values_ciphertext, p_requester_name_ciphertext,
    p_requester_email_hash, p_requester_email_ciphertext,
    p_requester_phone_hash, p_requester_phone_ciphertext,
    p_requested_start, p_requested_end, v_timezone
  )
  RETURNING id, status INTO v_inquiry_id, v_status;

  INSERT INTO eogp.public_booking_submission_idempotency (
    organization_id, key_fingerprint, request_fingerprint, inquiry_id
  ) VALUES (
    v_organization_id, p_key_fingerprint, p_request_fingerprint, v_inquiry_id
  );

  RETURN jsonb_build_object(
    'inquiryId', v_inquiry_id,
    'publicReference', v_public_reference,
    'status', v_status,
    'replayed', false
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.submit_public_booking_inquiry(
  text,text,uuid,text,text,text,bytea,bytea,text,bytea,text,bytea,timestamptz,timestamptz,text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.submit_public_booking_inquiry(
  text,text,uuid,text,text,text,bytea,bytea,text,bytea,text,bytea,timestamptz,timestamptz,text
) TO eventor_runtime;

COMMENT ON FUNCTION eogp.submit_public_booking_inquiry(
  text,text,uuid,text,text,text,bytea,bytea,text,bytea,text,bytea,timestamptz,timestamptz,text
) IS
  'Anonymous booking intake command. Resolves an active public tenant route, checks a published form revision, enforces durable per-source hourly limits and idempotency, and stores only application-encrypted requester/submission values.';
