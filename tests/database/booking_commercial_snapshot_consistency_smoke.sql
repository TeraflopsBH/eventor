-- Regression guards for the financial snapshot across offer preparation,
-- customer review, approval and final booking confirmation.
-- This is a runtime-role schema/contract smoke test, not an end-to-end fixture.
DO $test$
DECLARE
  v_save_definition text;
  v_staff_projection_definition text;
  v_public_projection_definition text;
  v_confirmation_definition text;
  v_offer_immutability_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'eogp.save_booking_offer_revision(uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,timestamptz,jsonb,jsonb,numeric,text,boolean)'::regprocedure
  ) INTO v_save_definition;

  -- The exact tax calculation and allocated adjustments must be persisted with
  -- the offer revision, not recalculated from whatever configuration is current.
  IF position('calculate_booking_offer_tax' IN v_save_definition)=0
     OR position('allocate_booking_offer_adjustment_tax' IN v_save_definition)=0
     OR position('taxCalculation' IN v_save_definition)=0
     OR position('v_adjustments:=v_adjustment_tax->''adjustments''' IN v_save_definition)=0
     OR position('''adjustments'',v_adjustments' IN v_save_definition)=0 THEN
    RAISE EXCEPTION 'offer preparation does not persist the calculated tax and allocated adjustment snapshot';
  END IF;

  SELECT pg_get_functiondef('eogp.get_booking_offer(uuid,uuid,uuid)'::regprocedure)
    INTO v_staff_projection_definition;
  IF position('''terms'',revision.terms_snapshot' IN v_staff_projection_definition)=0 THEN
    RAISE EXCEPTION 'staff offer projection no longer returns the persisted offer terms snapshot';
  END IF;

  SELECT pg_get_functiondef('eogp.get_public_booking_offer_with_capability(uuid,text)'::regprocedure)
    INTO v_public_projection_definition;

  -- Customer projection is an explicit allow-list: it exposes the agreed
  -- amounts and customer-readable line/adjustment descriptions, not internal
  -- calculation breakdowns, profile revision identifiers or audit metadata.
  IF position('''subtotal'',revision.subtotal' IN v_public_projection_definition)=0
     OR position('''taxAmount'',revision.tax_amount' IN v_public_projection_definition)=0
     OR position('''totalAmount'',revision.total_amount' IN v_public_projection_definition)=0
     OR position('''lineItems''' IN v_public_projection_definition)=0
     OR position('''adjustments''' IN v_public_projection_definition)=0 THEN
    RAISE EXCEPTION 'customer offer projection is missing one or more agreed financial amounts or terms';
  END IF;
  IF position('taxCalculation' IN v_public_projection_definition)>0
     OR position('taxAllocations' IN v_public_projection_definition)>0
     OR position('profileRevisionId' IN v_public_projection_definition)>0
     OR position('internalReason' IN v_public_projection_definition)>0
     OR position('approvalRequirements' IN v_public_projection_definition)>0
     OR position('actorMembershipId' IN v_public_projection_definition)>0
     OR position('reasonCiphertext' IN v_public_projection_definition)>0 THEN
    RAISE EXCEPTION 'customer offer projection exposes internal tax or audit data';
  END IF;

  SELECT pg_get_functiondef('eogp.confirm_booking_from_offer(uuid,uuid,uuid,text)'::regprocedure)
    INTO v_confirmation_definition;

  -- Confirmation must use the exact accepted offer revision and copy its
  -- persisted terms/amounts into the hashed booking snapshot.
  IF position('v_offer.status <> ''accepted''' IN v_confirmation_definition)=0
     OR position('v_revision.state <> ''accepted''' IN v_confirmation_definition)=0
     OR position('customer acceptance evidence for this offer revision is missing' IN v_confirmation_definition)=0
     OR position('v_revision.approval_requirements_snapshot' IN v_confirmation_definition)=0
     OR position('v_customer_terms := v_revision.terms_snapshot' IN v_confirmation_definition)=0
     OR position('''taxAmount'',v_revision.tax_amount' IN v_confirmation_definition)=0
     OR position('''totalAmount'',v_revision.total_amount' IN v_confirmation_definition)=0
     OR position('''terms'',v_revision.terms_snapshot' IN v_confirmation_definition)=0
     OR position('v_snapshot_sha256' IN v_confirmation_definition)=0 THEN
    RAISE EXCEPTION 'booking confirmation does not preserve the accepted offer financial snapshot and approval evidence';
  END IF;

  -- Issued offer terms cannot be edited or deleted. Only the terminal
  -- customer-decision state and accepted_at timestamp may change.
  SELECT pg_get_functiondef('eogp.protect_issued_booking_offer_revision()'::regprocedure)
    INTO v_offer_immutability_definition;
  IF NOT EXISTS (
    SELECT 1
      FROM pg_catalog.pg_trigger trigger_row
      JOIN pg_catalog.pg_class relation ON relation.oid=trigger_row.tgrelid
      JOIN pg_catalog.pg_namespace namespace ON namespace.oid=relation.relnamespace
     WHERE namespace.nspname='eogp'
       AND relation.relname='booking_offer_revisions'
       AND trigger_row.tgname='booking_offer_revisions_issued_immutable_guard'
       AND NOT trigger_row.tgisinternal
  ) OR position('to_jsonb(NEW)' IN v_offer_immutability_definition)=0
     OR position('to_jsonb(OLD)' IN v_offer_immutability_definition)=0
     OR position('issued booking offer terms are immutable' IN v_offer_immutability_definition)=0 THEN
    RAISE EXCEPTION 'issued offer revision terms are not protected by the immutability guard';
  END IF;

  -- Published tax-profile revisions are immutable; price-list immutability is
  -- checked by the existing commercial schema smoke test.
  IF NOT EXISTS (
    SELECT 1
      FROM pg_catalog.pg_trigger trigger_row
      JOIN pg_catalog.pg_class relation ON relation.oid=trigger_row.tgrelid
      JOIN pg_catalog.pg_namespace namespace ON namespace.oid=relation.relnamespace
     WHERE namespace.nspname='eogp'
       AND relation.relname='booking_tax_profile_revisions'
       AND trigger_row.tgname='booking_tax_profile_revisions_published_immutable_guard'
       AND NOT trigger_row.tgisinternal
  ) THEN
    RAISE EXCEPTION 'published tax-profile revision immutability guard is missing';
  END IF;
END;
$test$;
