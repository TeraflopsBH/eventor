-- Permission-checked booking draft projections and immutable successor revisions.
-- Drafts do not yet have a booking_records row, so draft permissions are granted
-- at organization scope. A booking-scoped grant cannot target a draft UUID.

INSERT INTO eogp.permissions (code, description, scope_kind, is_sensitive)
VALUES
  ('booking.draft.read', 'Read booking drafts and revision history', 'booking', true),
  ('booking.draft.manage', 'Create immutable successor revisions of booking drafts', 'booking', true)
ON CONFLICT (code) DO NOTHING;

CREATE FUNCTION eogp.assert_booking_draft_permission(
  p_organization_id uuid,
  p_draft_id uuid,
  p_actor_membership_id uuid,
  p_permission_code text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_membership_status text;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;

  IF p_permission_code NOT IN ('booking.draft.read','booking.draft.manage') THEN
    RAISE EXCEPTION 'unsupported booking draft permission' USING ERRCODE = '22023';
  END IF;

  SELECT membership.status
    INTO v_membership_status
    FROM eogp.organization_memberships membership
   WHERE membership.organization_id = p_organization_id
     AND membership.id = p_actor_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_membership_status <> 'active' THEN
    RAISE EXCEPTION 'active organization membership is required'
      USING ERRCODE = '42501';
  END IF;

  -- A draft is not a confirmed booking and cannot be the target of
  -- scope_booking_id. Only an organization grant can authorize a draft.
  PERFORM 1
    FROM eogp.user_role_grants user_grant
    JOIN eogp.role_permissions role_permission
      ON role_permission.organization_id = user_grant.organization_id
     AND role_permission.role_id = user_grant.role_id
   WHERE user_grant.organization_id = p_organization_id
     AND user_grant.membership_id = p_actor_membership_id
     AND user_grant.scope_kind = 'organization'
     AND user_grant.revoked_at IS NULL
     AND (user_grant.expires_at IS NULL OR user_grant.expires_at > clock_timestamp())
     AND role_permission.permission_code = p_permission_code
   FOR SHARE OF user_grant, role_permission;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'required booking draft permission is not granted'
      USING ERRCODE = '42501';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.assert_booking_draft_permission(uuid,uuid,uuid,text)
  FROM PUBLIC, eventor_runtime, eventor_worker, eventor_auth;

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
  v_can_read_draft boolean := false;
  v_can_manage_draft boolean := false;
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

  BEGIN
    PERFORM 1
      FROM eogp.user_role_grants user_grant
      JOIN eogp.role_permissions role_permission
        ON role_permission.organization_id = user_grant.organization_id
       AND role_permission.role_id = user_grant.role_id
     WHERE user_grant.organization_id = p_organization_id
       AND user_grant.membership_id = p_actor_membership_id
       AND user_grant.scope_kind = 'organization'
       AND user_grant.revoked_at IS NULL
       AND (user_grant.expires_at IS NULL OR user_grant.expires_at > clock_timestamp())
       AND role_permission.permission_code = 'booking.draft.read'
     FOR SHARE OF user_grant, role_permission;
    v_can_read_draft := FOUND;
  EXCEPTION WHEN insufficient_privilege THEN
    v_can_read_draft := false;
  END;

  BEGIN
    PERFORM 1
      FROM eogp.user_role_grants user_grant
      JOIN eogp.role_permissions role_permission
        ON role_permission.organization_id = user_grant.organization_id
       AND role_permission.role_id = user_grant.role_id
     WHERE user_grant.organization_id = p_organization_id
       AND user_grant.membership_id = p_actor_membership_id
       AND user_grant.scope_kind = 'organization'
       AND user_grant.revoked_at IS NULL
       AND (user_grant.expires_at IS NULL OR user_grant.expires_at > clock_timestamp())
       AND role_permission.permission_code = 'booking.draft.manage'
     FOR SHARE OF user_grant, role_permission;
    v_can_manage_draft := FOUND;
  EXCEPTION WHEN insufficient_privilege THEN
    v_can_manage_draft := false;
  END;

  RETURN jsonb_build_object(
    'canAssign', v_can_assign,
    'canManage', v_can_manage,
    'canAnnotate', v_can_annotate,
    'canConvert', v_can_convert,
    'canReadDraft', v_can_read_draft,
    'canManageDraft', v_can_manage_draft
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.get_booking_inquiry_capabilities(uuid,uuid)
  FROM PUBLIC, eventor_worker, eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.get_booking_inquiry_capabilities(uuid,uuid)
  TO eventor_runtime;

CREATE OR REPLACE FUNCTION eogp.get_booking_inquiry(
  p_organization_id uuid,
  p_inquiry_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  PERFORM eogp.assert_booking_inquiry_permission(
    p_organization_id, p_actor_membership_id, 'booking.inquiry.read'
  );

  SELECT jsonb_build_object(
    'inquiryId', inquiry.id,
    'publicReference', inquiry.public_reference,
    'status', inquiry.status,
    'formRevisionId', inquiry.form_revision_id,
    'fieldSchema', form_revision.field_schema,
    'requesterNameCiphertextBase64', encode(inquiry.requester_name_ciphertext,'base64'),
    'requesterEmailCiphertextBase64', CASE WHEN inquiry.requester_email_ciphertext IS NULL THEN NULL ELSE encode(inquiry.requester_email_ciphertext,'base64') END,
    'requesterPhoneCiphertextBase64', CASE WHEN inquiry.requester_phone_ciphertext IS NULL THEN NULL ELSE encode(inquiry.requester_phone_ciphertext,'base64') END,
    'submittedValuesCiphertextBase64', encode(inquiry.submitted_values_ciphertext,'base64'),
    'requestedStart', inquiry.requested_start,
    'requestedEnd', inquiry.requested_end,
    'requestedTimezone', inquiry.requested_timezone,
    'assignedToMembershipId', inquiry.assigned_to_membership_id,
    'submittedAt', inquiry.submitted_at,
    'updatedAt', inquiry.updated_at,
    'bookingDraft', (
      SELECT jsonb_build_object(
        'draftId', draft.id,
        'status', draft.status,
        'currentRevisionNumber', draft.current_revision_number
      )
        FROM eogp.booking_drafts draft
       WHERE draft.organization_id = inquiry.organization_id
         AND draft.source_inquiry_id = inquiry.id
    ),
    'annotations', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'annotationId', annotation.id,
        'annotation', annotation.annotation,
        'visibility', annotation.visibility,
        'actorMembershipId', annotation.actor_membership_id,
        'createdAt', annotation.created_at
      ) ORDER BY annotation.created_at, annotation.id),'[]'::jsonb)
        FROM eogp.booking_inquiry_annotations annotation
       WHERE annotation.organization_id = inquiry.organization_id
         AND annotation.inquiry_id = inquiry.id
         AND annotation.visibility = 'internal'
    ),
    'statusHistory', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'previousStatus', history.previous_status,
        'newStatus', history.new_status,
        'reason', history.reason,
        'actorKind', history.actor_kind,
        'actorMembershipId', history.actor_membership_id,
        'occurredAt', history.occurred_at
      ) ORDER BY history.occurred_at, history.id),'[]'::jsonb)
        FROM eogp.booking_inquiry_status_history history
       WHERE history.organization_id = inquiry.organization_id
         AND history.inquiry_id = inquiry.id
    ),
    'assignmentHistory', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'previousAssigneeMembershipId', history.previous_assignee_membership_id,
        'newAssigneeMembershipId', history.new_assignee_membership_id,
        'actorMembershipId', history.actor_membership_id,
        'occurredAt', history.occurred_at
      ) ORDER BY history.occurred_at, history.id),'[]'::jsonb)
        FROM eogp.booking_inquiry_assignment_history history
       WHERE history.organization_id = inquiry.organization_id
         AND history.inquiry_id = inquiry.id
    )
  )
    INTO v_result
    FROM eogp.booking_inquiries inquiry
    LEFT JOIN eogp.booking_form_revisions form_revision
      ON form_revision.organization_id = inquiry.organization_id
     AND form_revision.id = inquiry.form_revision_id
   WHERE inquiry.organization_id = p_organization_id
     AND inquiry.id = p_inquiry_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking inquiry not found' USING ERRCODE = 'P0002';
  END IF;
  RETURN v_result;
END;
$function$;

CREATE FUNCTION eogp.get_booking_draft(
  p_organization_id uuid,
  p_draft_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  PERFORM eogp.assert_booking_draft_permission(
    p_organization_id, p_draft_id, p_actor_membership_id, 'booking.draft.read'
  );

  SELECT jsonb_build_object(
    'draftId', draft.id,
    'sourceInquiryId', draft.source_inquiry_id,
    'status', draft.status,
    'currentRevisionNumber', draft.current_revision_number,
    'createdAt', draft.created_at,
    'updatedAt', draft.updated_at,
    'currentRevision', CASE WHEN revision.id IS NULL THEN NULL ELSE jsonb_build_object(
      'revisionId', revision.id,
      'revisionNumber', revision.revision_number,
      'sourceFormRevisionId', revision.source_form_revision_id,
      'fieldSchema', form_revision.field_schema,
      'valuesSnapshot', revision.values_snapshot,
      'requestedStart', revision.requested_start,
      'requestedEnd', revision.requested_end,
      'timezone', revision.timezone_name,
      'changeReason', revision.change_reason,
      'createdAt', revision.created_at,
      'createdByMembershipId', revision.created_by_membership_id,
      'spaceLines', (
        SELECT coalesce(jsonb_agg(jsonb_build_object(
          'spaceLineId', line.id,
          'venueSpaceId', line.venue_space_id,
          'blockKind', line.block_kind,
          'startsAt', line.starts_at,
          'endsAt', line.ends_at,
          'requestedCapacity', line.requested_capacity
        ) ORDER BY line.starts_at, line.id), '[]'::jsonb)
          FROM eogp.booking_draft_space_lines line
         WHERE line.organization_id = draft.organization_id
           AND line.draft_revision_id = revision.id
      ),
      'resourceLines', (
        SELECT coalesce(jsonb_agg(jsonb_build_object(
          'resourceLineId', line.id,
          'resourceTypeId', line.resource_type_id,
          'lineCode', line.line_code,
          'label', line.label_snapshot,
          'requestedQuantity', line.requested_quantity,
          'values', line.value_snapshot
        ) ORDER BY line.line_code, line.id), '[]'::jsonb)
          FROM eogp.booking_resource_lines line
         WHERE line.organization_id = draft.organization_id
           AND line.draft_revision_id = revision.id
      )
    ) END,
    'revisionHistory', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'revisionId', item.id,
        'revisionNumber', item.revision_number,
        'changeReason', item.change_reason,
        'createdAt', item.created_at,
        'createdByMembershipId', item.created_by_membership_id,
        'createdByDisplayName', users.display_name
      ) ORDER BY item.revision_number DESC), '[]'::jsonb)
        FROM eogp.booking_draft_revisions item
        JOIN eogp.organization_memberships membership
          ON membership.organization_id = item.organization_id
         AND membership.id = item.created_by_membership_id
        JOIN eogp.users users ON users.id = membership.user_id
       WHERE item.organization_id = draft.organization_id
         AND item.draft_id = draft.id
    )
  )
    INTO v_result
    FROM eogp.booking_drafts draft
    LEFT JOIN eogp.booking_draft_revisions revision
      ON revision.organization_id = draft.organization_id
     AND revision.draft_id = draft.id
     AND revision.revision_number = draft.current_revision_number
    LEFT JOIN eogp.booking_form_revisions form_revision
      ON form_revision.organization_id = revision.organization_id
     AND form_revision.id = revision.source_form_revision_id
   WHERE draft.organization_id = p_organization_id
     AND draft.id = p_draft_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking draft not found' USING ERRCODE = 'P0002';
  END IF;
  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.get_booking_draft(uuid,uuid,uuid)
  FROM PUBLIC, eventor_worker, eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.get_booking_draft(uuid,uuid,uuid)
  TO eventor_runtime;

CREATE FUNCTION eogp.create_booking_draft_revision(
  p_organization_id uuid,
  p_draft_id uuid,
  p_actor_membership_id uuid,
  p_expected_revision_number integer,
  p_values_ciphertext bytea,
  p_requested_start timestamptz,
  p_requested_end timestamptz,
  p_timezone text,
  p_space_lines jsonb,
  p_resource_lines jsonb,
  p_change_reason text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_draft eogp.booking_drafts%ROWTYPE;
  v_current_revision_id uuid;
  v_current_source_form_revision_id uuid;
  v_next_revision_number integer;
  v_revision_id uuid := gen_random_uuid();
  v_line jsonb;
  v_space_id uuid;
  v_space_capacity integer;
  v_starts_at timestamptz;
  v_ends_at timestamptz;
  v_block_kind text;
  v_requested_capacity integer;
  v_resource_type_id uuid;
  v_resource_code text;
  v_resource_name text;
  v_resource_quantity numeric(12,3);
  v_resource_values jsonb;
  v_line_index integer := 0;
BEGIN
  PERFORM eogp.assert_booking_draft_permission(
    p_organization_id, p_draft_id, p_actor_membership_id, 'booking.draft.manage'
  );

  SELECT *
    INTO v_draft
    FROM eogp.booking_drafts
   WHERE organization_id = p_organization_id
     AND id = p_draft_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking draft not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_draft.status <> 'draft' THEN
    RAISE EXCEPTION 'only a draft in draft status can be revised'
      USING ERRCODE = '55000';
  END IF;
  IF p_expected_revision_number IS NULL
     OR p_expected_revision_number <> v_draft.current_revision_number THEN
    RAISE EXCEPTION 'booking draft revision is stale; reload before saving'
      USING ERRCODE = '40001';
  END IF;
  IF p_change_reason IS NULL OR length(btrim(p_change_reason)) < 3
     OR length(p_change_reason) > 2000 THEN
    RAISE EXCEPTION 'a change reason between 3 and 2000 characters is required'
      USING ERRCODE = '22023';
  END IF;
  IF p_values_ciphertext IS NULL
     OR octet_length(p_values_ciphertext) <= 32
     OR substring(p_values_ciphertext FROM 1 FOR 4) <> convert_to('ECP1','UTF8') THEN
    RAISE EXCEPTION 'draft values must use the ECP1 encrypted envelope'
      USING ERRCODE = '22023';
  END IF;
  IF p_timezone IS NULL OR length(btrim(p_timezone)) < 1 OR length(p_timezone) > 80
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = p_timezone) THEN
    RAISE EXCEPTION 'a valid timezone is required'
      USING ERRCODE = '22023';
  END IF;
  IF p_requested_start IS NOT NULL AND p_requested_end IS NOT NULL
     AND p_requested_end <= p_requested_start THEN
    RAISE EXCEPTION 'requested end must follow requested start'
      USING ERRCODE = '22023';
  END IF;
  IF p_space_lines IS NULL OR jsonb_typeof(p_space_lines) <> 'array'
     OR jsonb_array_length(p_space_lines) > 50 THEN
    RAISE EXCEPTION 'spaceLines must be an array of at most 50 entries'
      USING ERRCODE = '22023';
  END IF;
  IF p_resource_lines IS NULL OR jsonb_typeof(p_resource_lines) <> 'array'
     OR jsonb_array_length(p_resource_lines) > 100 THEN
    RAISE EXCEPTION 'resourceLines must be an array of at most 100 entries'
      USING ERRCODE = '22023';
  END IF;

  IF v_draft.current_revision_number > 0 THEN
    SELECT revision.id, revision.source_form_revision_id
      INTO v_current_revision_id, v_current_source_form_revision_id
      FROM eogp.booking_draft_revisions revision
     WHERE revision.organization_id = p_organization_id
       AND revision.draft_id = p_draft_id
       AND revision.revision_number = v_draft.current_revision_number
     FOR SHARE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'current booking draft revision is missing'
        USING ERRCODE = '55000';
    END IF;

    IF EXISTS (
      SELECT 1
        FROM eogp.resource_reservations reservation
       WHERE reservation.organization_id = p_organization_id
         AND reservation.booking_draft_revision_id = v_current_revision_id
         AND reservation.status = 'held'
         AND reservation.expires_at > clock_timestamp()
    ) OR EXISTS (
      SELECT 1
        FROM eogp.venue_space_time_blocks block
       WHERE block.organization_id = p_organization_id
         AND block.booking_draft_revision_id = v_current_revision_id
         AND block.status = 'held'
         AND block.expires_at > clock_timestamp()
    ) THEN
      RAISE EXCEPTION 'active resource/space holds must expire or be released before revising this draft'
        USING ERRCODE = '55000';
    END IF;
  ELSE
    v_current_source_form_revision_id := NULL;
  END IF;

  INSERT INTO eogp.booking_draft_revisions (
    id, organization_id, draft_id, revision_number, source_form_revision_id,
    values_snapshot, requested_start, requested_end, timezone_name,
    change_reason, created_by_membership_id
  ) VALUES (
    v_revision_id, p_organization_id, p_draft_id,
    v_draft.current_revision_number + 1,
    v_current_source_form_revision_id,
    jsonb_build_object(
      'schemaVersion', 1,
      'encryption', 'ECP1',
      'contactKind', 'other',
      'ciphertextBase64', encode(p_values_ciphertext,'base64')
    ),
    p_requested_start, p_requested_end, p_timezone,
    btrim(p_change_reason), p_actor_membership_id
  );
  v_next_revision_number := v_draft.current_revision_number + 1;

  FOR v_line IN SELECT value FROM jsonb_array_elements(p_space_lines)
  LOOP
    v_line_index := v_line_index + 1;
    IF jsonb_typeof(v_line) <> 'object' THEN
      RAISE EXCEPTION 'each space line must be an object' USING ERRCODE = '22023';
    END IF;
    BEGIN
      v_space_id := (v_line->>'venueSpaceId')::uuid;
      v_starts_at := (v_line->>'startsAt')::timestamptz;
      v_ends_at := (v_line->>'endsAt')::timestamptz;
      v_block_kind := v_line->>'blockKind';
      v_requested_capacity := CASE
        WHEN v_line ? 'requestedCapacity' AND v_line->'requestedCapacity' <> 'null'::jsonb
          THEN (v_line->>'requestedCapacity')::integer
        ELSE NULL
      END;
    EXCEPTION WHEN invalid_text_representation OR datetime_field_overflow THEN
      RAISE EXCEPTION 'space line % contains an invalid UUID, timestamp or integer', v_line_index
        USING ERRCODE = '22023';
    END;
    IF v_space_id IS NULL OR v_starts_at IS NULL OR v_ends_at IS NULL
       OR v_ends_at <= v_starts_at
       OR v_block_kind NOT IN ('setup','rehearsal','event_use','teardown','buffer')
       OR (v_requested_capacity IS NOT NULL AND v_requested_capacity < 0) THEN
      RAISE EXCEPTION 'space line % has invalid required values', v_line_index
        USING ERRCODE = '22023';
    END IF;

    SELECT space.capacity
      INTO v_space_capacity
      FROM eogp.venue_spaces space
     WHERE space.organization_id = p_organization_id
       AND space.id = v_space_id
       AND space.status = 'active'
     FOR SHARE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'space line % refers to an unavailable venue space', v_line_index
        USING ERRCODE = '23503';
    END IF;
    IF v_requested_capacity IS NOT NULL AND v_space_capacity IS NOT NULL
       AND v_requested_capacity > v_space_capacity THEN
      RAISE EXCEPTION 'space line % exceeds the venue space capacity', v_line_index
        USING ERRCODE = '22023';
    END IF;

    INSERT INTO eogp.booking_draft_space_lines (
      organization_id, draft_revision_id, venue_space_id, block_kind,
      starts_at, ends_at, requested_capacity
    ) VALUES (
      p_organization_id, v_revision_id, v_space_id, v_block_kind,
      v_starts_at, v_ends_at, v_requested_capacity
    );
  END LOOP;

  v_line_index := 0;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_resource_lines)
  LOOP
    v_line_index := v_line_index + 1;
    IF jsonb_typeof(v_line) <> 'object' THEN
      RAISE EXCEPTION 'each resource line must be an object' USING ERRCODE = '22023';
    END IF;
    BEGIN
      v_resource_type_id := (v_line->>'resourceTypeId')::uuid;
      v_resource_quantity := (v_line->>'requestedQuantity')::numeric(12,3);
    EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      RAISE EXCEPTION 'resource line % contains an invalid UUID or quantity', v_line_index
        USING ERRCODE = '22023';
    END;
    v_resource_values := coalesce(v_line->'values','{}'::jsonb);
    IF v_resource_type_id IS NULL OR v_resource_quantity IS NULL
       OR v_resource_quantity <= 0 OR v_resource_quantity::text IN ('NaN','Infinity','-Infinity')
       OR jsonb_typeof(v_resource_values) <> 'object' THEN
      RAISE EXCEPTION 'resource line % has invalid required values', v_line_index
        USING ERRCODE = '22023';
    END IF;

    SELECT resource_type.code, resource_type.name
      INTO v_resource_code, v_resource_name
      FROM eogp.resource_types resource_type
     WHERE resource_type.organization_id = p_organization_id
       AND resource_type.id = v_resource_type_id
       AND resource_type.reservable = true
     FOR SHARE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'resource line % refers to an unavailable/non-reservable resource type', v_line_index
        USING ERRCODE = '23503';
    END IF;

    INSERT INTO eogp.booking_resource_lines (
      organization_id, draft_revision_id, resource_type_id, line_code,
      label_snapshot, requested_quantity, value_snapshot
    ) VALUES (
      p_organization_id, v_revision_id, v_resource_type_id,
      v_resource_code || '-' || lpad(v_line_index::text,2,'0'),
      v_resource_name, v_resource_quantity, v_resource_values
    );
  END LOOP;

  UPDATE eogp.booking_drafts
     SET current_revision_number = v_next_revision_number,
         updated_at = clock_timestamp()
   WHERE organization_id = p_organization_id
     AND id = p_draft_id;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, reason_code, safe_metadata
  ) VALUES (
    p_organization_id, p_organization_id, p_actor_membership_id, 'membership',
    'booking.draft.revised', 'booking_draft', p_draft_id, 'revision_created',
    jsonb_build_object(
      'revisionId', v_revision_id,
      'revisionNumber', v_next_revision_number,
      'previousRevisionNumber', v_draft.current_revision_number,
      'spaceLineCount', jsonb_array_length(p_space_lines),
      'resourceLineCount', jsonb_array_length(p_resource_lines)
    )
  );

  RETURN jsonb_build_object(
    'draftId', p_draft_id,
    'revisionId', v_revision_id,
    'revisionNumber', v_next_revision_number,
    'previousRevisionNumber', v_draft.current_revision_number,
    'status', v_draft.status,
    'changed', true
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.create_booking_draft_revision(uuid,uuid,uuid,integer,bytea,timestamptz,timestamptz,text,jsonb,jsonb,text)
  FROM PUBLIC, eventor_worker, eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.create_booking_draft_revision(uuid,uuid,uuid,integer,bytea,timestamptz,timestamptz,text,jsonb,jsonb,text)
  TO eventor_runtime;

COMMENT ON FUNCTION eogp.get_booking_draft(uuid,uuid,uuid) IS
  'Returns the authorized current draft revision, field schema, space/resource lines and revision history. Ciphertext stays encrypted until the API authorizes and decrypts it.';
COMMENT ON FUNCTION eogp.create_booking_draft_revision(uuid,uuid,uuid,integer,bytea,timestamptz,timestamptz,text,jsonb,jsonb,text) IS
  'Creates an immutable successor draft revision using optimistic revision checking, tenant-bound ECP1 values encryption and permission-checked active venue/resource line references. Active holds on the prior revision must first expire or be released.';
