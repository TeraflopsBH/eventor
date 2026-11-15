\set ON_ERROR_STOP on
BEGIN;

-- Run through eventor_runtime. The SMTP race fixture supplies the live
-- invitation capability; all RSVP writes below roll back with this transaction.
DO $guest_rsvp_capability_write_limit$
DECLARE
  v_token_sha256 text := repeat('f',64);
  v_history jsonb;
  v_baseline_count integer;
  v_denied boolean := false;
  i integer;
BEGIN
  v_history := eogp.get_guest_invitation_rsvp_history(v_token_sha256);
  v_baseline_count := jsonb_array_length(v_history);

  FOR i IN 1..20 LOOP
    PERFORM eogp.submit_guest_invitation_rsvp(
      v_token_sha256,
      lpad(to_hex(i),64,'0'),
      lpad(to_hex(i+100),64,'0'),
      'accepted',
      NULL
    );
  END LOOP;

  v_history := eogp.get_guest_invitation_rsvp_history(v_token_sha256);
  IF jsonb_array_length(v_history)<>v_baseline_count+20 THEN
    RAISE EXCEPTION 'expected 20 additional guest RSVP history rows, got % from baseline %',
      jsonb_array_length(v_history),v_baseline_count;
  END IF;

  BEGIN
    PERFORM eogp.submit_guest_invitation_rsvp(
      v_token_sha256,
      lpad(to_hex(21),64,'0'),
      lpad(to_hex(121),64,'0'),
      'accepted',
      NULL
    );
  EXCEPTION WHEN SQLSTATE '54000' THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'guest invitation accepted a 21st distinct RSVP submission';
  END IF;

  v_history := eogp.get_guest_invitation_rsvp_history(v_token_sha256);
  IF jsonb_array_length(v_history)<>v_baseline_count+20 THEN
    RAISE EXCEPTION 'rejected 21st RSVP appended response history; count is % from baseline %',
      jsonb_array_length(v_history),v_baseline_count;
  END IF;
END;
$guest_rsvp_capability_write_limit$;

ROLLBACK;
\echo 'Guest invitation RSVP per-link write limit regression passed.'
