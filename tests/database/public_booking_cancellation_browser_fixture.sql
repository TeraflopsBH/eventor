-- Synthetic independent bookings for the Chromium and Firefox customer journeys.
-- Apply after the main migration smoke data and provider browser grants.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','10000000-0000-0000-0000-00000000000a',true);
DO $fixture$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_policy CONSTANT uuid := 'a5000000-0000-0000-0000-00000000000a';
  v_engine text;
  v_booking uuid;
  v_contact uuid;
  v_draft uuid;
  v_revision uuid;
  v_offer uuid;
  v_offer_revision uuid;
BEGIN
  FOREACH v_engine IN ARRAY ARRAY['chromium','firefox'] LOOP
    v_booking := CASE v_engine WHEN 'chromium' THEN '79000000-0000-4000-8000-0000000000a1'::uuid ELSE '79000000-0000-4000-8000-0000000000b1'::uuid END;
    v_contact := CASE v_engine WHEN 'chromium' THEN '79000000-0000-4000-8000-0000000000a2'::uuid ELSE '79000000-0000-4000-8000-0000000000b2'::uuid END;
    v_draft := gen_random_uuid(); v_revision := gen_random_uuid();
    v_offer := gen_random_uuid(); v_offer_revision := gen_random_uuid();
    INSERT INTO eogp.booking_drafts(id,organization_id,created_by_membership_id) VALUES(v_draft,v_org,v_actor);
    INSERT INTO eogp.booking_draft_revisions(id,organization_id,draft_id,revision_number,values_snapshot,created_by_membership_id)
      VALUES(v_revision,v_org,v_draft,1,'{}',v_actor);
    INSERT INTO eogp.booking_offers(id,organization_id,draft_id,status) VALUES(v_offer,v_org,v_draft,'accepted');
    INSERT INTO eogp.booking_offer_revisions(id,organization_id,offer_id,revision_number,draft_revision_id,
      cancellation_policy_revision_id,terms_snapshot,currency,subtotal,tax_amount,total_amount,state,issued_at,accepted_at)
      VALUES(v_offer_revision,v_org,v_offer,1,v_revision,v_policy,'{}','BAM',0,0,0,'accepted',clock_timestamp(),clock_timestamp());
    INSERT INTO eogp.booking_records(id,organization_id,booking_code,source_offer_revision_id)
      VALUES(v_booking,v_org,'CI-PUBLIC-CANCEL-'||v_engine,v_offer_revision);
    INSERT INTO eogp.booking_confirmed_snapshots(organization_id,booking_id,offer_revision_id,cancellation_policy_revision_id,
      customer_terms_snapshot,price_snapshot,confirmed_by_membership_id,snapshot_sha256)
      VALUES(v_org,v_booking,v_offer_revision,v_policy,'{}','{}',v_actor,repeat('f',64));
    INSERT INTO eogp.booking_party_contacts(id,organization_id,booking_id,party_role,display_name_ciphertext,
      email_hash,email_ciphertext,authorized_actions)
      VALUES(v_contact,v_org,v_booking,'authorized_booking_contact',convert_to('EV1synthetic-contact','UTF8'),
        encode(eogp.digest(convert_to(v_engine||'@example.invalid','UTF8'),'sha256'),'hex'),
        convert_to('EV1synthetic-email','UTF8'),ARRAY['booking_cancellation_request','booking_cancellation_status']);
  END LOOP;
END;
$fixture$;
COMMIT;
