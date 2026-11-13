-- Commercial draft resource holds must be attributable to requested resource lines.
-- Older booking drafts may legitimately use the generic reservation workflow
-- without commercial resource lines; preserve that legacy path. Once a draft
-- revision has commercial resource lines, however, every reservation for it
-- must reference one of those lines.

DO $migration$
BEGIN
  IF EXISTS (
    SELECT 1
      FROM eogp.resource_reservations reservation
      JOIN eogp.booking_resource_lines line
        ON line.organization_id = reservation.organization_id
       AND line.draft_revision_id = reservation.booking_draft_revision_id
     WHERE reservation.booking_draft_revision_id IS NOT NULL
       AND reservation.booking_resource_line_id IS NULL
  ) THEN
    RAISE EXCEPTION
      'cannot enforce commercial draft resource-line attribution: existing reservations are unlinked';
  END IF;
END;
$migration$;

CREATE FUNCTION eogp.enforce_commercial_draft_resource_reservation_line()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  IF NEW.booking_draft_revision_id IS NOT NULL
     AND NEW.booking_resource_line_id IS NULL
     AND EXISTS (
       SELECT 1
         FROM eogp.booking_resource_lines line
        WHERE line.organization_id = NEW.organization_id
          AND line.draft_revision_id = NEW.booking_draft_revision_id
     ) THEN
    RAISE EXCEPTION
      'commercial draft resource reservations must reference a resource line'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE TRIGGER resource_reservations_commercial_draft_line_guard
BEFORE INSERT OR UPDATE OF organization_id, booking_draft_revision_id, booking_resource_line_id
ON eogp.resource_reservations
FOR EACH ROW
EXECUTE FUNCTION eogp.enforce_commercial_draft_resource_reservation_line();

-- Also prevent adding the first commercial line after an unlinked hold has
-- already been created for the same draft revision.
CREATE FUNCTION eogp.prevent_commercial_resource_lines_with_unlinked_holds()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  IF EXISTS (
    SELECT 1
      FROM eogp.resource_reservations reservation
     WHERE reservation.organization_id = NEW.organization_id
       AND reservation.booking_draft_revision_id = NEW.draft_revision_id
       AND reservation.booking_resource_line_id IS NULL
  ) THEN
    RAISE EXCEPTION
      'cannot add commercial resource lines while unlinked draft resource reservations exist'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE TRIGGER booking_resource_lines_unlinked_hold_guard
BEFORE INSERT OR UPDATE OF organization_id, draft_revision_id
ON eogp.booking_resource_lines
FOR EACH ROW
EXECUTE FUNCTION eogp.prevent_commercial_resource_lines_with_unlinked_holds();
