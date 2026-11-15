\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','22222222-2222-4222-8222-222222222222',true);

INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind)
VALUES (
  '96100000-0000-4000-8000-000000000001',
  '22222222-2222-4222-8222-222222222222',
  'ci-booking-offer-email-worker',
  'CI booking offer email worker fixture',
  'organization'
);
INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
VALUES
 ('22222222-2222-4222-8222-222222222222','96100000-0000-4000-8000-000000000001','booking.inquiry.convert'),
 ('22222222-2222-4222-8222-222222222222','96100000-0000-4000-8000-000000000001','booking.manage'),
 ('22222222-2222-4222-8222-222222222222','96100000-0000-4000-8000-000000000001','booking.draft.manage'),
 ('22222222-2222-4222-8222-222222222222','96100000-0000-4000-8000-000000000001','booking.approve');
INSERT INTO eogp.user_role_grants(
  organization_id,membership_id,role_id,scope_kind,granted_by_membership_id
) VALUES (
 '22222222-2222-4222-8222-222222222222',
 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
 '96100000-0000-4000-8000-000000000001',
 'organization',
 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
);

INSERT INTO eogp.booking_form_definitions(
  id,organization_id,scope_kind,form_code,name,status
) VALUES (
 '96200000-0000-4000-8000-000000000001',
 '22222222-2222-4222-8222-222222222222',
 'organization','ci-offer-email','CI offer email form','active'
);
INSERT INTO eogp.booking_form_revisions(
  id,organization_id,form_definition_id,revision_number,locale,field_schema,state,published_at
) VALUES (
 '96300000-0000-4000-8000-000000000001',
 '22222222-2222-4222-8222-222222222222',
 '96200000-0000-4000-8000-000000000001',
 1,'bs-BA',
 '{"schemaVersion":1,"fields":[{"code":"event_date","type":"date","required":true},{"code":"event_name","type":"text","required":true}]}'::jsonb,
 'published',clock_timestamp()
);

DO $fixture$
DECLARE
  v_org uuid := '22222222-2222-4222-8222-222222222222';
  v_actor uuid := 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';
  v_ciphertext bytea := decode('45435031'||repeat('00',29),'hex');
  v_submitted jsonb;
  v_conversion jsonb;
  v_tax jsonb;
  v_price jsonb;
  v_cancellation jsonb;
  v_approval jsonb;
  v_offer jsonb;
  v_queued jsonb;
  v_inquiry_id uuid;
  v_draft_revision_id uuid;
  v_tax_profile_id uuid;
  v_tax_revision_id uuid;
  v_price_list_id uuid;
  v_price_revision_id uuid;
  v_cancellation_policy_id uuid;
  v_cancellation_revision_id uuid;
  v_approval_policy_id uuid;
  v_approval_revision_id uuid;
  v_offer_id uuid;
  v_token text := repeat('A',43);
  v_token_hash text;
  v_tax_codes jsonb := '[{"taxCode":"STANDARD","label":"Standard rate","treatment":"percentage","rate":0}]'::jsonb;
  v_approval_rules jsonb := '[{"code":"commercial-review","condition":{"kind":"always"},"requiredApprovals":1,"permission":"booking.approve","separationOfDuties":true}]'::jsonb;
BEGIN
  v_submitted := eogp.submit_public_booking_inquiry_with_locale(
    'ci-venue-b','ci-offer-email','96300000-0000-4000-8000-000000000001',
    repeat('1',64),repeat('2',64),repeat('3',64),
    v_ciphertext,v_ciphertext,
    NULL,NULL,NULL,NULL,
    clock_timestamp()+interval '10 days',
    clock_timestamp()+interval '10 days 4 hours',
    'Europe/Sarajevo','bs-BA'
  );
  IF v_submitted->>'status'<>'received' THEN
    RAISE EXCEPTION 'synthetic booking inquiry was not accepted: %',v_submitted;
  END IF;
  v_inquiry_id := (v_submitted->>'inquiryId')::uuid;

  v_conversion := eogp.convert_booking_inquiry_to_draft(v_org,v_inquiry_id,v_actor);
  IF v_conversion->>'status'<>'converted' THEN
    RAISE EXCEPTION 'synthetic booking inquiry did not convert to a draft: %',v_conversion;
  END IF;
  v_draft_revision_id := (v_conversion->>'revisionId')::uuid;

  v_tax := eogp.create_booking_tax_profile(
    v_org,v_actor,'CI-OFFER-EMAIL-TAX','CI offer email tax','BA','CI-REG','BAM','exclusive'
  );
  v_tax_profile_id := (v_tax->>'taxProfileId')::uuid;
  v_tax_revision_id := (v_tax->>'revisionId')::uuid;
  PERFORM eogp.update_booking_tax_profile_draft_revision(
    v_org,v_tax_profile_id,v_tax_revision_id,v_actor,'BA','CI-REG','BAM',
    'exclusive','invoice_total',2,NULL,NULL,v_tax_codes
  );
  PERFORM eogp.publish_booking_tax_profile_revision(
    v_org,v_tax_profile_id,v_tax_revision_id,v_actor
  );

  v_price := eogp.create_booking_price_list(
    v_org,v_actor,'CI-OFFER-EMAIL-PRICE','CI offer email price list',
    'organization',NULL,NULL,'BAM','exclusive'
  );
  v_price_list_id := (v_price->>'priceListId')::uuid;
  v_price_revision_id := (v_price->>'revisionId')::uuid;
  PERFORM eogp.replace_booking_price_list_draft_items(
    v_org,v_price_list_id,v_price_revision_id,v_actor,'BAM','exclusive',NULL,NULL,
    '[{"itemCode":"ROOM","label":"Meeting room","unit":"hour","unitAmount":125.00,"quantityMin":1,"taxCode":"STANDARD"}]'::jsonb
  );
  PERFORM eogp.set_booking_price_list_tax_profile_revision(
    v_org,v_price_list_id,v_price_revision_id,v_tax_revision_id,v_actor
  );
  PERFORM eogp.publish_booking_price_list_revision(
    v_org,v_price_list_id,v_price_revision_id,v_actor
  );

  v_cancellation := eogp.create_booking_cancellation_policy(
    v_org,v_actor,'CI-OFFER-EMAIL-CANCEL','CI offer email cancellation'
  );
  v_cancellation_policy_id := (v_cancellation->>'policyId')::uuid;
  v_cancellation := eogp.create_booking_cancellation_policy_revision(
    v_org,v_cancellation_policy_id,v_actor,'request_only','CI cancellation terms',
    '{}'::jsonb,'{}'::jsonb,'{}'::jsonb
  );
  v_cancellation_revision_id := (v_cancellation->>'revisionId')::uuid;
  PERFORM eogp.publish_booking_cancellation_policy_revision(
    v_org,v_cancellation_policy_id,v_cancellation_revision_id,v_actor
  );

  v_approval := eogp.create_booking_approval_policy(
    v_org,v_actor,'CI-OFFER-EMAIL-APPROVAL','CI offer email approval'
  );
  v_approval_policy_id := (v_approval->>'policyId')::uuid;
  v_approval := eogp.create_booking_approval_policy_revision(
    v_org,v_approval_policy_id,v_actor,v_approval_rules
  );
  v_approval_revision_id := (v_approval->>'revisionId')::uuid;
  PERFORM eogp.publish_booking_approval_policy_revision(
    v_org,v_approval_policy_id,v_approval_revision_id,v_actor
  );

  PERFORM set_config('app.actor_membership_id',v_actor::text,true);
  v_offer := eogp.save_booking_offer_revision(
    v_org,v_draft_revision_id,v_actor,NULL,v_price_revision_id,
    v_cancellation_revision_id,v_approval_revision_id,
    'BAM','exclusive',clock_timestamp()+interval '2 days',
    '[{"itemCode":"ROOM","quantity":1}]'::jsonb,'[]'::jsonb,
    0,'CI booking offer email worker fixture',false
  );
  v_offer_id := (v_offer->>'offerId')::uuid;
  v_token_hash := encode(eogp.digest(convert_to(v_token,'UTF8'),'sha256'),'hex');
  PERFORM eogp.issue_booking_offer(v_org,v_offer_id,v_actor,v_token_hash);

  v_queued := eogp.queue_booking_offer_email_delivery(
    v_org,v_offer_id,v_actor,
    repeat('4',64),v_token_hash,
    convert_to('ECP1'||repeat('x',64),'UTF8')
  );
  IF v_queued->>'status'<>'queued' OR v_queued->>'created'<>'true' THEN
    RAISE EXCEPTION 'booking offer email was not queued: %',v_queued;
  END IF;

END;
$fixture$;

COMMIT;
\echo 'Persistent synthetic booking-offer email fixture prepared.';
