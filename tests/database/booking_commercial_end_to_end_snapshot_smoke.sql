-- End-to-end transactional verification of the commercial offer -> customer
-- acceptance -> approval -> booking confirmation path.
-- Runs as the migrator/owner, creates isolated synthetic actors/configuration,
-- invokes the production command functions, and rolls every change back.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','11111111-1111-4111-8111-111111111111',true);

DO $test$
DECLARE
  v_org uuid := '11111111-1111-4111-8111-111111111111';
  v_creator uuid := 'dddddddd-4444-4444-8444-dddddddddddd';
  v_creator_user uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  v_approver uuid := 'cccccccc-3333-4333-8333-cccccccccccc';
  v_approver_user uuid := 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  v_creator_role uuid := gen_random_uuid();
  v_approver_role uuid := gen_random_uuid();
  v_draft_id uuid := gen_random_uuid();
  v_draft_revision_id uuid := gen_random_uuid();
  v_tax_profile_id uuid;
  v_tax_revision_1 uuid;
  v_tax_revision_2 uuid;
  v_price_list_id uuid;
  v_price_revision_1 uuid;
  v_price_revision_2 uuid;
  v_cancellation_policy_id uuid;
  v_cancellation_revision_1 uuid;
  v_cancellation_revision_2 uuid;
  v_approval_policy_id uuid;
  v_approval_revision_1 uuid;
  v_approval_revision_2 uuid;
  v_offer_id uuid;
  v_offer_revision_id uuid;
  v_booking_id uuid;
  v_token_sha256 text := repeat('a',64);
  v_prepared jsonb;
  v_result jsonb;
  v_public_offer jsonb;
  v_confirmation jsonb;
  v_snapshot eogp.booking_confirmed_snapshots%ROWTYPE;
  v_expected_snapshot_sha256 text;
  v_tax_codes_v1 jsonb := '[{"taxCode":"STANDARD","label":"Standard rate","treatment":"percentage","rate":20}]'::jsonb;
  v_tax_codes_v2 jsonb := '[{"taxCode":"STANDARD","label":"Standard rate","treatment":"percentage","rate":30}]'::jsonb;
  v_approval_rules_v1 jsonb := '[{"code":"commercial-review","condition":{"kind":"always"},"requiredApprovals":1,"permission":"booking.approve","separationOfDuties":true}]'::jsonb;
  v_approval_rules_v2 jsonb := '[{"code":"commercial-review","condition":{"kind":"always"},"requiredApprovals":2,"permission":"booking.approve","separationOfDuties":true}]'::jsonb;
  v_cancellation_approval_rules jsonb := '{}'::jsonb;
  v_cancellation_commercial_rules jsonb := '{}'::jsonb;
  v_cancellation_notice_rules jsonb := '{}'::jsonb;
  v_line_items jsonb := '[{"itemCode":"ROOM","quantity":1}]'::jsonb;
  v_adjustments jsonb := '[
    {"code":"facility-fee","label":"Facility fee","kind":"fee","amount":10.00,"allocationMethod":"tax_code","taxCode":"STANDARD"},
    {"code":"partner-discount","label":"Partner discount","kind":"discount","amount":10.00,"allocationMethod":"proportional_to_lines"}
  ]'::jsonb;
  v_ciphertext bytea := convert_to('ECP1'||repeat('synthetic-customer-name-',3),'UTF8');
BEGIN
  -- The second actor is an isolated approver in the same tenant. The creator
  -- cannot approve because the pinned policy requires separation of duties.
  INSERT INTO eogp.users(id,email,display_name,status)
  VALUES
    (v_creator_user,'ci-commercial-creator@example.invalid','CI Commercial Creator','active'),
    (v_approver_user,'ci-commercial-approver@example.invalid','CI Commercial Approver','active');
  INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status,joined_at)
  VALUES
    (v_creator,v_org,v_creator_user,'active',clock_timestamp()),
    (v_approver,v_org,v_approver_user,'active',clock_timestamp());

  INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind)
  VALUES
    (v_creator_role,v_org,'ci-commercial-creator-'||replace(gen_random_uuid()::text,'-',''),'CI commercial creator','organization'),
    (v_approver_role,v_org,'ci-commercial-approver-'||replace(gen_random_uuid()::text,'-',''),'CI commercial approver','organization');
  INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
  VALUES
    (v_org,v_creator_role,'booking.manage'),
    (v_org,v_creator_role,'booking.confirm'),
    (v_org,v_approver_role,'booking.approve');
  INSERT INTO eogp.user_role_grants(
    organization_id,membership_id,role_id,scope_kind,granted_by_membership_id
  ) VALUES
    (v_org,v_creator,v_creator_role,'organization',v_creator),
    (v_org,v_approver,v_approver_role,'organization',v_creator);

  -- Minimal direct-draft fixture: no space/resource lines, so final resource
  -- availability preflight must correctly accept the empty requested inventory.
  INSERT INTO eogp.booking_drafts(
    id,organization_id,created_by_membership_id,status,current_revision_number
  ) VALUES(v_draft_id,v_org,v_creator,'draft',1);
  INSERT INTO eogp.booking_draft_revisions(
    id,organization_id,draft_id,revision_number,values_snapshot,timezone_name,
    change_reason,created_by_membership_id
  ) VALUES(v_draft_revision_id,v_org,v_draft_id,1,'{"fixture":"commercial-snapshot"}',
    'Europe/Sarajevo','End-to-end commercial snapshot fixture',v_creator);

  -- Publish tax profile revision 1 at 20%.
  v_result:=eogp.create_booking_tax_profile(v_org,v_creator,
    'CI-E2E-TAX-'||substr(gen_random_uuid()::text,1,8),'CI E2E tax profile',
    'CI','CI-REG','USD','exclusive');
  v_tax_profile_id:=(v_result->>'taxProfileId')::uuid;
  v_tax_revision_1:=(v_result->>'revisionId')::uuid;
  PERFORM eogp.update_booking_tax_profile_draft_revision(
    v_org,v_tax_profile_id,v_tax_revision_1,v_creator,'CI','CI-REG','USD',
    'exclusive','invoice_total',2,NULL,NULL,v_tax_codes_v1
  );
  PERFORM eogp.publish_booking_tax_profile_revision(
    v_org,v_tax_profile_id,v_tax_revision_1,v_creator
  );

  -- Publish price-list revision 1 with one $100 line and the pinned 20% profile.
  v_result:=eogp.create_booking_price_list(v_org,v_creator,
    'CI-E2E-PRICE-'||substr(gen_random_uuid()::text,1,8),'CI E2E price list',
    'organization',NULL,NULL,'USD','exclusive');
  v_price_list_id:=(v_result->>'priceListId')::uuid;
  v_price_revision_1:=(v_result->>'revisionId')::uuid;
  PERFORM eogp.replace_booking_price_list_draft_items(
    v_org,v_price_list_id,v_price_revision_1,v_creator,'USD','exclusive',NULL,NULL,
    '[{"itemCode":"ROOM","label":"Meeting room","unit":"day","unitAmount":100.00,"quantityMin":1,"taxCode":"STANDARD"}]'::jsonb
  );
  PERFORM eogp.set_booking_price_list_tax_profile_revision(
    v_org,v_price_list_id,v_price_revision_1,v_tax_revision_1,v_creator
  );
  PERFORM eogp.publish_booking_price_list_revision(
    v_org,v_price_list_id,v_price_revision_1,v_creator
  );

  -- Publish cancellation terms and a one-approval policy with separation of duties.
  v_result:=eogp.create_booking_cancellation_policy(v_org,v_creator,
    'CI-E2E-CANCEL-'||substr(gen_random_uuid()::text,1,8),'CI E2E cancellation policy');
  v_cancellation_policy_id:=(v_result->>'policyId')::uuid;
  v_result:=eogp.create_booking_cancellation_policy_revision(
    v_org,v_cancellation_policy_id,v_creator,'request_only','Cancellation terms version 1',
    v_cancellation_approval_rules,v_cancellation_commercial_rules,v_cancellation_notice_rules
  );
  v_cancellation_revision_1:=(v_result->>'revisionId')::uuid;
  PERFORM eogp.publish_booking_cancellation_policy_revision(
    v_org,v_cancellation_policy_id,v_cancellation_revision_1,v_creator
  );

  v_result:=eogp.create_booking_approval_policy(v_org,v_creator,
    'CI-E2E-APPROVAL-'||substr(gen_random_uuid()::text,1,8),'CI E2E approval policy');
  v_approval_policy_id:=(v_result->>'policyId')::uuid;
  v_result:=eogp.create_booking_approval_policy_revision(
    v_org,v_approval_policy_id,v_creator,v_approval_rules_v1
  );
  v_approval_revision_1:=(v_result->>'revisionId')::uuid;
  PERFORM eogp.publish_booking_approval_policy_revision(
    v_org,v_approval_policy_id,v_approval_revision_1,v_creator
  );

  -- The offer-creator trigger captures the authenticated actor for separation-of-duties checks.
  PERFORM set_config('app.actor_membership_id',v_creator::text,true);

  -- Prepare the offer through the real command. The $10 fee and $10 discount
  -- both affect the taxable base; the 20% result is therefore $20 tax.
  v_prepared:=eogp.save_booking_offer_revision(
    v_org,v_draft_revision_id,v_creator,NULL,v_price_revision_1,
    v_cancellation_revision_1,v_approval_revision_1,'USD','exclusive',
    clock_timestamp()+interval '2 days',v_line_items,v_adjustments,0,
    'End-to-end snapshot test adjustments',false
  );
  v_offer_id:=(v_prepared->>'offerId')::uuid;
  v_offer_revision_id:=(v_prepared->>'offerRevisionId')::uuid;

  IF (v_prepared->>'subtotal')::numeric<>100.00
     OR (v_prepared->>'taxAmount')::numeric<>20.00
     OR (v_prepared->>'totalAmount')::numeric<>120.00 THEN
    RAISE EXCEPTION 'offer preparation calculated unexpected totals: %',v_prepared;
  END IF;

  -- Issue the exact revision and verify the real customer projection before
  -- the configuration catalogue advances.
  PERFORM eogp.issue_booking_offer(v_org,v_offer_id,v_creator,v_token_sha256);
  v_public_offer:=eogp.get_public_booking_offer_with_capability(v_offer_id,v_token_sha256);
  IF (v_public_offer->>'subtotal')::numeric<>100.00
     OR (v_public_offer->>'taxAmount')::numeric<>20.00
     OR (v_public_offer->>'totalAmount')::numeric<>120.00
     OR v_public_offer->'terms'->>'cancellationTerms'<>'Cancellation terms version 1'
     OR v_public_offer->'terms' ? 'taxCalculation'
     OR v_public_offer->'terms' ? 'taxAllocations'
     OR v_public_offer->'terms' ? 'profileRevisionId' THEN
    RAISE EXCEPTION 'customer projection does not expose the agreed amounts safely: %',v_public_offer;
  END IF;

  -- Publish tax-profile and price-list revision 2 with materially different
  -- values. Neither may rewrite the issued offer revision.
  v_result:=eogp.create_booking_tax_profile_revision(
    v_org,v_tax_profile_id,v_creator,'CI','CI-REG','USD','exclusive',
    'invoice_total',2,NULL,NULL
  );
  v_tax_revision_2:=(v_result->>'revisionId')::uuid;
  PERFORM eogp.update_booking_tax_profile_draft_revision(
    v_org,v_tax_profile_id,v_tax_revision_2,v_creator,'CI','CI-REG','USD',
    'exclusive','invoice_total',2,NULL,NULL,v_tax_codes_v2
  );
  PERFORM eogp.publish_booking_tax_profile_revision(
    v_org,v_tax_profile_id,v_tax_revision_2,v_creator
  );

  v_result:=eogp.create_booking_price_list_revision(
    v_org,v_price_list_id,v_creator,'USD','exclusive',NULL,NULL
  );
  v_price_revision_2:=(v_result->>'revisionId')::uuid;
  PERFORM eogp.replace_booking_price_list_draft_items(
    v_org,v_price_list_id,v_price_revision_2,v_creator,'USD','exclusive',NULL,NULL,
    '[{"itemCode":"ROOM","label":"Meeting room revised","unit":"day","unitAmount":250.00,"quantityMin":1,"taxCode":"STANDARD"}]'::jsonb
  );
  PERFORM eogp.set_booking_price_list_tax_profile_revision(
    v_org,v_price_list_id,v_price_revision_2,v_tax_revision_2,v_creator
  );
  PERFORM eogp.publish_booking_price_list_revision(
    v_org,v_price_list_id,v_price_revision_2,v_creator
  );

  -- Advance both other policy catalogues too. Confirmation must use the
  -- requirements and cancellation terms pinned in offer revision 1.
  v_result:=eogp.create_booking_cancellation_policy_revision(
    v_org,v_cancellation_policy_id,v_creator,'request_only','Cancellation terms version 2',
    v_cancellation_approval_rules,v_cancellation_commercial_rules,v_cancellation_notice_rules
  );
  v_cancellation_revision_2:=(v_result->>'revisionId')::uuid;
  PERFORM eogp.publish_booking_cancellation_policy_revision(
    v_org,v_cancellation_policy_id,v_cancellation_revision_2,v_creator
  );

  v_result:=eogp.create_booking_approval_policy_revision(
    v_org,v_approval_policy_id,v_creator,v_approval_rules_v2
  );
  v_approval_revision_2:=(v_result->>'revisionId')::uuid;
  PERFORM eogp.publish_booking_approval_policy_revision(
    v_org,v_approval_policy_id,v_approval_revision_2,v_creator
  );

  -- The customer still sees revision 1 terms and totals after all four
  -- catalogues have advanced. The offer has not been silently repriced.
  v_public_offer:=eogp.get_public_booking_offer_with_capability(v_offer_id,v_token_sha256);
  IF (v_public_offer->>'subtotal')::numeric<>100.00
     OR (v_public_offer->>'taxAmount')::numeric<>20.00
     OR (v_public_offer->>'totalAmount')::numeric<>120.00
     OR v_public_offer->'terms'->>'cancellationTerms'<>'Cancellation terms version 1' THEN
    RAISE EXCEPTION 'published successor configuration changed the issued customer offer: %',v_public_offer;
  END IF;

  -- Customer acceptance is recorded through the single-use capability command.
  v_result:=eogp.decide_booking_offer_with_capability(
    v_offer_id,v_token_sha256,'accepted',repeat('b',64),repeat('c',64),
    v_ciphertext,NULL,NULL,NULL
  );
  IF v_result->>'decision'<>'accepted' OR coalesce((v_result->>'replayed')::boolean,true) THEN
    RAISE EXCEPTION 'customer acceptance did not create a new accepted decision: %',v_result;
  END IF;

  -- The offer creator must be rejected by the separation-of-duties gate.
  BEGIN
    PERFORM eogp.decide_booking_offer_approval(
      v_org,v_offer_id,v_offer_revision_id,v_creator,
      'commercial-review','approved','Creator must not self-approve'
    );
    RAISE EXCEPTION 'offer creator unexpectedly approved their own offer';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  -- Only the independent approver may satisfy the pinned one-approval rule.
  v_result:=eogp.decide_booking_offer_approval(
    v_org,v_offer_id,v_offer_revision_id,v_approver,
    'commercial-review','approved','CI independent approval'
  );
  IF v_result->>'satisfied'<>'true' THEN
    RAISE EXCEPTION 'pinned approval requirement was not satisfied: %',v_result;
  END IF;

  -- Confirmation uses the accepted revision and pinned one-approval rule,
  -- even though policy revision 2 now asks for two approvals.
  v_confirmation:=eogp.confirm_booking_from_offer(
    v_org,v_draft_revision_id,v_creator,'CI accepted offer confirmation'
  );
  v_booking_id:=(v_confirmation->>'bookingId')::uuid;
  IF v_confirmation->>'status'<>'confirmed'
     OR coalesce((v_confirmation->>'replayed')::boolean,true) THEN
    RAISE EXCEPTION 'accepted offer did not produce a new confirmed booking: %',v_confirmation;
  END IF;

  SELECT * INTO v_snapshot
    FROM eogp.booking_confirmed_snapshots
   WHERE organization_id=v_org AND booking_id=v_booking_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'confirmed booking snapshot was not persisted';
  END IF;

  IF v_snapshot.offer_revision_id IS DISTINCT FROM v_offer_revision_id
     OR v_snapshot.cancellation_policy_revision_id IS DISTINCT FROM v_cancellation_revision_1
     OR v_snapshot.price_snapshot->>'currency'<>'USD'
     OR (v_snapshot.price_snapshot->>'subtotal')::numeric<>100.00
     OR (v_snapshot.price_snapshot->>'taxAmount')::numeric<>20.00
     OR (v_snapshot.price_snapshot->>'totalAmount')::numeric<>120.00
     OR v_snapshot.price_snapshot->'terms'->'taxConfiguration'->>'taxProfileRevisionId'<>v_tax_revision_1::text
     OR v_snapshot.price_snapshot->'terms'->>'cancellationTerms'<>'Cancellation terms version 1'
     OR (v_snapshot.price_snapshot->'terms'->'taxCalculation'->>'taxAmount')::numeric<>20.00
     OR v_snapshot.price_snapshot->'terms'->'adjustments'->0->'taxAllocations'->0->>'taxCode'<>'STANDARD'
     OR v_snapshot.price_snapshot->'terms'->'adjustments'->1->'allocationMethod'<>'proportional_to_lines' THEN
    RAISE EXCEPTION 'confirmed price snapshot does not preserve the exact accepted financial terms: %',v_snapshot.price_snapshot;
  END IF;

  v_expected_snapshot_sha256:=encode(eogp.digest(convert_to(jsonb_build_object(
    'customerTerms',v_snapshot.customer_terms_snapshot,
    'price',v_snapshot.price_snapshot,
    'cancellationPolicyRevisionId',v_snapshot.cancellation_policy_revision_id
  )::text,'UTF8'),'sha256'),'hex');
  IF v_snapshot.snapshot_sha256<>v_expected_snapshot_sha256 THEN
    RAISE EXCEPTION 'confirmed snapshot hash does not match its immutable content';
  END IF;

  -- The original published price and tax revisions remain unchanged while
  -- successor revisions hold the new values.
  IF (SELECT unit_amount FROM eogp.booking_price_items
       WHERE organization_id=v_org AND price_list_revision_id=v_price_revision_1 AND item_code='ROOM')<>100.00
     OR (SELECT unit_amount FROM eogp.booking_price_items
       WHERE organization_id=v_org AND price_list_revision_id=v_price_revision_2 AND item_code='ROOM')<>250.00
     OR (SELECT (tax_codes->0->>'rate')::numeric FROM eogp.booking_tax_profile_revisions
       WHERE organization_id=v_org AND id=v_tax_revision_1)<>20
     OR (SELECT (tax_codes->0->>'rate')::numeric FROM eogp.booking_tax_profile_revisions
       WHERE organization_id=v_org AND id=v_tax_revision_2)<>30 THEN
    RAISE EXCEPTION 'publishing successor revisions mutated a prior price or tax revision';
  END IF;

  -- Issued offer terms and published tax configuration are protected from
  -- direct mutation, even when the test runs with the migration owner role.
  BEGIN
    UPDATE eogp.booking_offer_revisions
       SET terms_snapshot=terms_snapshot||'{"tampered":true}'::jsonb
     WHERE organization_id=v_org AND id=v_offer_revision_id;
    RAISE EXCEPTION 'issued offer terms unexpectedly accepted mutation';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;
  BEGIN
    UPDATE eogp.booking_tax_profile_revisions
       SET tax_codes=v_tax_codes_v2
     WHERE organization_id=v_org AND id=v_tax_revision_1;
    RAISE EXCEPTION 'published tax profile revision unexpectedly accepted mutation';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;

  -- Re-read after the rejected mutation attempts to ensure no financial drift.
  IF (SELECT total_amount FROM eogp.booking_offer_revisions
       WHERE organization_id=v_org AND id=v_offer_revision_id)<>120.00
     OR (SELECT (price_snapshot->>'totalAmount')::numeric FROM eogp.booking_confirmed_snapshots
       WHERE organization_id=v_org AND booking_id=v_booking_id)<>120.00 THEN
    RAISE EXCEPTION 'offer or confirmed snapshot changed after attempted mutation';
  END IF;
END;
$test$;

ROLLBACK;
