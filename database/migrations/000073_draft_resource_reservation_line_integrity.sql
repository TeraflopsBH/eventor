-- Draft resource holds must always be attributable to a requested resource line.
-- Confirmation converts every live hold on the draft revision; allowing an
-- unlinked hold would turn unrequested inventory into confirmed occupancy.
DO $migration$
BEGIN
  IF EXISTS (
    SELECT 1
      FROM eogp.resource_reservations reservation
     WHERE reservation.booking_draft_revision_id IS NOT NULL
       AND reservation.booking_resource_line_id IS NULL
  ) THEN
    RAISE EXCEPTION
      'cannot enforce draft resource-line attribution: existing draft reservations contain unlinked rows';
  END IF;
END;
$migration$;

ALTER TABLE eogp.resource_reservations
  ADD CONSTRAINT resource_reservations_draft_requires_resource_line
  CHECK (
    booking_draft_revision_id IS NULL
    OR booking_resource_line_id IS NOT NULL
  );
