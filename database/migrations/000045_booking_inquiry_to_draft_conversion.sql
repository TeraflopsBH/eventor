-- Convert a reviewed public inquiry into a separate booking draft atomically.
-- The original inquiry and its encrypted submission remain unchanged.
INSERT INTO eogp.permissions (code, description, scope_kind, is_sensitive)
VALUES (
  'booking.inquiry.convert',
  'Convert a reviewed booking inquiry into a booking draft',
  'booking',
  true
)
ON CONFLICT (code) DO NOTHING;

-- An inquiry may be the source of at most one draft, even if another command
-- path is introduced later.
CREATE UNIQUE INDEX booking_drafts_source_inquiry_unique_idx
  ON eogp.booking_drafts (organization_id, source_inquiry_id)
  WHERE source_inquiry_id IS NOT NULL;

-- Extend the capability projection without exposing grant rows or identity data.
CREATE OR REPLACE FUNCTION eogp.get_booking_inquiry_capabilities(
  p_organization_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_can_assign boolean := false;
  v_can_manage boolean := false;
  v_can_annotate boolean := false;
  v_can_convert boolean := false;
BEGIN
  PERFORM eogp.assert_booking_inquiry_permission(
    p_organization_id, p_actor_membership_id, 'booking.inquiry.read'
  );

  BEGIN
    PERFORM eogp.assert_booking_inquiry_permission(
      p_organization_id, p_actor_membership_id, 'booking.inquiry.assign'
    );
    v_can_assign := true;
  EXCEPTION WHEN insufficient_privilege THEN
    v_can_assign := false;
  END;

  BEGIN
    PERFORM eogp.assert_booking_inquiry_permission(
      p_organization_id, p_actor_membership_id, 'booking.inquiry.manage'
    );
    v_can_manage := true;
  EXCEPTION WHEN insufficient_privilege THEN
    v_can_manage := false;
  END;

  BEGIN
    PERFORM eogp.assert_booking_inquiry_permission(
      p_organization_id, p_actor_membership_id, 'booking.inquiry.annotate'
    );
    v_can_annotate := true;
  EXCEPTION WHEN insufficient_privilege THEN
    v_can_annotate := false;
  END;

  BEGIN
    PERFORM eogp.assert_booking_inquiry_permission(
      p_organization_id, p_actor_membership_id, 'booking.inquiry.convert'
    );
    v_can_convert := true;
  EXCEPTION WHEN insufficient_privilege THEN
    v_can_convert := false;
  END;

  RETURN jsonb_build_object(
    'canAssign', v_can_assign,
    'canManage', v_can_manage,
    'canAnnotate', v_can_annotate,
    'canConvert', v_can_convert
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.get_booking_inquiry_capabilities(uuid,uuid)
  FROM PUBLIC, eventor_worker, eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.get_booking_inquiry_capabilities(uuid,uuid)
  TO eventor_runtime;

CREATE FUNCTION eogp.convert_booking_inquiry_to_draft(
  p_organization_id uuid,
  p_inquiry_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_status text;
  v_form_revision_id uuid;
  v_submitted_values_ciphertext bytea;
  v_requested_start timestamptz;
  v_requested_end timestamptz;
  v_requested_timezone text;
  v_draft_id uuid;
  v_revision_id uuid;
  v_current_revision_number integer;
BEGIN
  PERFORM eogp.assert_booking_inquiry_permission(
    p_organization_id, p_actor_membership_id, 'booking.inquiry.convert'
  );

  SELECT inquiry.status,
         inquiry.form_revision_id,
         inquiry.submitted_values_ciphertext,
         inquiry.requested_start,
         inquiry.requested_end,
         inquiry.requested_timezone
    INTO v_status,
         v_form_revision_id,
         v_submitted_values_ciphertext,
         v_requested_start,
         v_requested_end,
         v_requested_timezone
    FROM eogp.booking_inquiries AS inquiry
   WHERE inquiry.organization_id = p_organization_id
     AND inquiry.id = p_inquiry_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking inquiry not found' USING ERRCODE = 'P0002';
  END IF;

  -- A retried command returns the existing conversion result without creating
  -- another draft, revision, history event or audit event.
  IF v_status = 'converted' THEN
    SELECT draft.id, draft.current_revision_number
      INTO v_draft_id, v_current_revision_number
      FROM eogp.booking_drafts AS draft
     WHERE draft.organization_id = p_organization_id
       AND draft.source_inquiry_id = p_inquiry_id
     FOR UPDATE;

    IF NOT FOUND OR v_current_revision_number < 1 THEN
      RAISE EXCEPTION 'converted inquiry is missing its booking draft'
        USING ERRCODE = '55000';
    END IF;

    SELECT revision.id
      INTO v_revision_id
      FROM eogp.booking_draft_revisions AS revision
     WHERE revision.organization_id = p_organization_id
       AND revision.draft_id = v_draft_id
       AND revision.revision_number = 1;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'converted inquiry draft is missing its initial revision'
        USING ERRCODE = '55000';
    END IF;

    RETURN jsonb_build_object(
      'inquiryId', p_inquiry_id,
      'draftId', v_draft_id,
      'revisionId', v_revision_id,
      'revisionNumber', 1,
      'status', 'converted',
      'changed', false
    );
  END IF;

  IF v_status NOT IN ('received','under_review') THEN
    RAISE EXCEPTION 'only received or under-review inquiries can be converted'
      USING ERRCODE = '55000';
  END IF;

  -- Fail closed if an inconsistent pre-existing draft is found for an open
  -- inquiry. The unique index remains the final invariant under concurrency.
  IF EXISTS (
    SELECT 1
      FROM eogp.booking_drafts AS draft
     WHERE draft.organization_id = p_organization_id
       AND draft.source_inquiry_id = p_inquiry_id
  ) THEN
    RAISE EXCEPTION 'open inquiry already has a booking draft'
      USING ERRCODE = '55000';
  END IF;

  -- Only copy a recognized ECP1 envelope. Never project decrypted answers
  -- into JSONB: the draft revision stores the ciphertext in an explicit,
  -- versioned wrapper and keeps the original inquiry as the source of truth.
  IF v_submitted_values_ciphertext IS NULL
     OR octet_length(v_submitted_values_ciphertext) <= 32
     OR substring(v_submitted_values_ciphertext FROM 1 FOR 4) <> convert_to('ECP1','UTF8') THEN
    RAISE EXCEPTION 'inquiry submission ciphertext is missing or unsupported'
      USING ERRCODE = '55000';
  END IF;

  INSERT INTO eogp.booking_drafts (
    organization_id,
    source_inquiry_id,
    created_by_membership_id,
    status,
    current_revision_number
  ) VALUES (
    p_organization_id,
    p_inquiry_id,
    p_actor_membership_id,
    'draft',
    0
  )
  RETURNING id INTO v_draft_id;

  INSERT INTO eogp.booking_draft_revisions (
    organization_id,
    draft_id,
    revision_number,
    source_form_revision_id,
    values_snapshot,
    requested_start,
    requested_end,
    timezone_name,
    change_reason,
    created_by_membership_id
  ) VALUES (
    p_organization_id,
    v_draft_id,
    1,
    v_form_revision_id,
    jsonb_build_object(
      'schemaVersion', 1,
      'encryption', 'ECP1',
      'contactKind', 'other',
      'ciphertextBase64', encode(v_submitted_values_ciphertext, 'base64')
    ),
    v_requested_start,
    v_requested_end,
    v_requested_timezone,
    'converted_from_public_inquiry',
    p_actor_membership_id
  )
  RETURNING id INTO v_revision_id;

  UPDATE eogp.booking_drafts
     SET current_revision_number = 1,
         updated_at = clock_timestamp()
   WHERE organization_id = p_organization_id
     AND id = v_draft_id;

  UPDATE eogp.booking_inquiries
     SET status = 'converted',
         updated_at = clock_timestamp()
   WHERE organization_id = p_organization_id
     AND id = p_inquiry_id;

  INSERT INTO eogp.booking_inquiry_status_history (
    organization_id,
    inquiry_id,
    previous_status,
    new_status,
    reason,
    actor_kind,
    actor_membership_id
  ) VALUES (
    p_organization_id,
    p_inquiry_id,
    v_status,
    'converted',
    'converted_to_booking_draft',
    'membership',
    p_actor_membership_id
  );

  INSERT INTO eogp.audit_events (
    organization_id,
    actor_organization_id,
    actor_membership_id,
    actor_kind,
    action,
    aggregate_type,
    aggregate_id,
    reason_code,
    safe_metadata
  ) VALUES (
    p_organization_id,
    p_organization_id,
    p_actor_membership_id,
    'membership',
    'booking.inquiry.converted',
    'booking_inquiry',
    p_inquiry_id,
    'converted_to_booking_draft',
    jsonb_build_object(
      'draftId', v_draft_id,
      'revisionId', v_revision_id,
      'revisionNumber', 1
    )
  );

  RETURN jsonb_build_object(
    'inquiryId', p_inquiry_id,
    'draftId', v_draft_id,
    'revisionId', v_revision_id,
    'revisionNumber', 1,
    'status', 'converted',
    'changed', true
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.convert_booking_inquiry_to_draft(uuid,uuid,uuid)
  FROM PUBLIC, eventor_worker, eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.convert_booking_inquiry_to_draft(uuid,uuid,uuid)
  TO eventor_runtime;

-- Drafts, draft revisions, draft space lines, resource lines and offers are exposed
-- only through permission-checked commands and projections. The immutable
-- revisions remain inaccessible as raw table rows.
REVOKE ALL ON
  eogp.booking_drafts,
  eogp.booking_draft_revisions,
  eogp.booking_draft_space_lines,
  eogp.booking_offers,
  eogp.booking_offer_revisions,
  eogp.booking_resource_lines
FROM PUBLIC, eventor_runtime, eventor_worker, eventor_auth;

COMMENT ON FUNCTION eogp.convert_booking_inquiry_to_draft(uuid,uuid,uuid) IS
  'Atomically creates revision 1 of a separate booking draft from an open inquiry, preserving the original encrypted submission and appending the inquiry conversion history/audit event. Replays return the existing draft.';
