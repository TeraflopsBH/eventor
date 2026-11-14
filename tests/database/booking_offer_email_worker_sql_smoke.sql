\set ON_ERROR_STOP on
BEGIN;
SET LOCAL app.organization_id='33333333-3333-4333-8333-333333333333';

DO $booking_offer_email_worker$
DECLARE
  v_claim_count integer;
  v_result_type text;
  v_claim_definition text;
  v_completion_definition text;
  v_missing_lease_rejected boolean := false;
BEGIN
  IF session_user<>'eventor_worker' THEN
    RAISE EXCEPTION 'booking-offer email worker smoke test must run as eventor_worker';
  END IF;

  -- The historical return type was declared TEXT while the source column is
  -- CHAR(3). Keep the SQL contract explicit so the worker receives the type
  -- promised by RETURNS TABLE.
  v_result_type:=pg_get_function_result(
    'eogp.claim_booking_offer_email_delivery(uuid)'::regprocedure
  );
  IF position('currency text' IN v_result_type)=0 THEN
    RAISE EXCEPTION 'claim function currency result must be text: %',v_result_type;
  END IF;

  -- These are security-definer worker commands. The worker is represented by
  -- the supported service_principal actor kind, never the invalid "system".
  v_claim_definition:=pg_get_functiondef(
    'eogp.claim_booking_offer_email_delivery(uuid)'::regprocedure
  );
  v_completion_definition:=pg_get_functiondef(
    'eogp.complete_booking_offer_email_delivery(uuid,uuid,text,text,text)'::regprocedure
  );
  IF position('service_principal' IN v_claim_definition)=0
     OR position('service_principal' IN v_completion_definition)=0
     OR position('''system''' IN v_claim_definition)>0
     OR position('''system''' IN v_completion_definition)>0 THEN
    RAISE EXCEPTION 'booking-offer worker audit attribution must use service_principal';
  END IF;

  -- Calling the claim function with an empty tenant executes both UPDATE
  -- RETURNING CTEs and catches PL/pgSQL output-column ambiguity at runtime.
  SELECT count(*) INTO v_claim_count
    FROM eogp.claim_booking_offer_email_delivery(
      '33333333-3333-4333-8333-333333333333'
    );
  IF v_claim_count<>0 THEN
    RAISE EXCEPTION 'isolated empty-tenant claim unexpectedly returned a delivery';
  END IF;

  -- Exercise completion-function compilation and its lease guard without
  -- creating or sending a real email.
  BEGIN
    PERFORM eogp.complete_booking_offer_email_delivery(
      '33333333-3333-4333-8333-333333333333',
      '44444444-4444-4444-8444-444444444444',
      'sent',NULL,'ci-no-send'
    );
    RAISE EXCEPTION 'completion accepted a nonexistent delivery lease';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_missing_lease_rejected:=true;
  END;
  IF NOT v_missing_lease_rejected THEN
    RAISE EXCEPTION 'completion did not reject a missing delivery lease';
  END IF;
END;
$booking_offer_email_worker$;

ROLLBACK;

\echo 'Booking-offer email worker SQL contract smoke tests passed.'
