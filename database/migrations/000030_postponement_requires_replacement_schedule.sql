-- Align the event change request invariant with the accepted postponement
-- workflow: a postponement and a reschedule both create a pinned replacement
-- schedule revision. Existing inconsistent postponed requests are not repaired
-- by inventing dates; stop and require an operator decision before upgrading.

DO $preflight$
DECLARE
  v_count bigint;
BEGIN
  SELECT count(*)
    INTO v_count
    FROM eogp.event_change_requests
   WHERE change_kind = 'postpone'
     AND replacement_schedule_revision_id IS NULL;

  IF v_count > 0 THEN
    RAISE EXCEPTION
      '000030 requires review of % existing postponement request(s) without a replacement schedule',
      v_count
      USING ERRCODE = '23514',
            HINT = 'Reconcile each postponed request with its approved replacement schedule before retrying this migration; do not fabricate dates.';
  END IF;
END;
$preflight$;

ALTER TABLE eogp.event_change_requests
  DROP CONSTRAINT event_change_requests_check3;

ALTER TABLE eogp.event_change_requests
  ADD CONSTRAINT event_change_requests_replacement_schedule_check
  CHECK (
    (change_kind IN ('postpone','reschedule'))
    = (replacement_schedule_revision_id IS NOT NULL)
  );
