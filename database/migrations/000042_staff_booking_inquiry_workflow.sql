-- Staff-side booking inquiry inbox, assignment, history and internal notes.
-- Inquiry records are exposed only through permission-checked projections and
-- commands; runtime roles do not select the encrypted source tables directly.

INSERT INTO eogp.permissions (code, description, scope_kind, is_sensitive) VALUES
  ('booking.inquiry.assign','Assign booking inquiries to active organization members','booking',true),
  ('booking.inquiry.manage','Change booking inquiry review status','booking',true),
  ('booking.inquiry.annotate','Add internal booking inquiry notes','booking',true)
ON CONFLICT (code) DO NOTHING;

ALTER TABLE eogp.booking_inquiries
  ADD COLUMN assigned_to_membership_id uuid,
  ADD COLUMN updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  ADD CONSTRAINT booking_inquiries_assignee_fk
    FOREIGN KEY (organization_id, assigned_to_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id);

CREATE INDEX booking_inquiries_assignee_inbox_idx
  ON eogp.booking_inquiries (organization_id, assigned_to_membership_id, submitted_at DESC)
  WHERE status IN ('received','under_review');

CREATE TABLE eogp.booking_inquiry_status_history (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    inquiry_id uuid NOT NULL,
    previous_status text,
    new_status text NOT NULL
      CHECK (new_status IN ('received','under_review','converted','declined','withdrawn','spam')),
    reason text,
    actor_kind text NOT NULL CHECK (actor_kind IN ('public','membership')),
    actor_membership_id uuid,
    occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, inquiry_id)
      REFERENCES eogp.booking_inquiries(organization_id, id),
    FOREIGN KEY (organization_id, actor_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    CHECK (
      (actor_kind = 'public' AND actor_membership_id IS NULL)
      OR (actor_kind = 'membership' AND actor_membership_id IS NOT NULL)
    )
);

CREATE INDEX booking_inquiry_status_history_order_idx
  ON eogp.booking_inquiry_status_history (organization_id, inquiry_id, occurred_at, id);

CREATE TABLE eogp.booking_inquiry_assignment_history (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    inquiry_id uuid NOT NULL,
    previous_assignee_membership_id uuid,
    new_assignee_membership_id uuid,
    actor_membership_id uuid NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, inquiry_id)
      REFERENCES eogp.booking_inquiries(organization_id, id),
    FOREIGN KEY (organization_id, previous_assignee_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    FOREIGN KEY (organization_id, new_assignee_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    FOREIGN KEY (organization_id, actor_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    CHECK (previous_assignee_membership_id IS DISTINCT FROM new_assignee_membership_id)
);

CREATE INDEX booking_inquiry_assignment_history_order_idx
  ON eogp.booking_inquiry_assignment_history (organization_id, inquiry_id, occurred_at, id);

ALTER TABLE eogp.booking_inquiry_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.booking_inquiry_status_history FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation
  ON eogp.booking_inquiry_status_history
  USING (organization_id = eogp.current_organization_id())
  WITH CHECK (organization_id = eogp.current_organization_id());

ALTER TABLE eogp.booking_inquiry_assignment_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.booking_inquiry_assignment_history FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation
  ON eogp.booking_inquiry_assignment_history
  USING (organization_id = eogp.current_organization_id())
  WITH CHECK (organization_id = eogp.current_organization_id());

-- Preserve an initial receipt record for all new public inquiries. This trigger
-- also gives pre-existing rows a backfilled "received" state during deployment.
CREATE FUNCTION eogp.record_initial_booking_inquiry_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  INSERT INTO eogp.booking_inquiry_status_history (
    organization_id, inquiry_id, previous_status, new_status,
    reason, actor_kind, actor_membership_id
  ) VALUES (
    NEW.organization_id, NEW.id, NULL, NEW.status,
    'public_submission', 'public', NULL
  );
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.record_initial_booking_inquiry_status() FROM PUBLIC;

CREATE TRIGGER booking_inquiry_initial_status_history
AFTER INSERT ON eogp.booking_inquiries
FOR EACH ROW EXECUTE FUNCTION eogp.record_initial_booking_inquiry_status();

DO $backfill$
DECLARE
  v_organization_id uuid;
BEGIN
  FOR v_organization_id IN
    SELECT DISTINCT organization_id FROM eogp.booking_inquiries ORDER BY organization_id
  LOOP
    PERFORM set_config('app.organization_id',v_organization_id::text,true);
    INSERT INTO eogp.booking_inquiry_status_history (
      organization_id, inquiry_id, previous_status, new_status,
      reason, actor_kind, actor_membership_id
    )
    SELECT inquiry.organization_id, inquiry.id, NULL, inquiry.status,
           'migration_backfill', 'public', NULL
      FROM eogp.booking_inquiries inquiry
     WHERE inquiry.organization_id = v_organization_id
       AND NOT EXISTS (
         SELECT 1 FROM eogp.booking_inquiry_status_history history
          WHERE history.organization_id = inquiry.organization_id
            AND history.inquiry_id = inquiry.id
       );
  END LOOP;
END;
$backfill$;

-- These tables are immutable event records. All writes are mediated by
-- SECURITY DEFINER commands which enforce membership permissions.
CREATE TRIGGER booking_inquiry_status_history_append_only
BEFORE UPDATE OR DELETE ON eogp.booking_inquiry_status_history
FOR EACH ROW EXECUTE FUNCTION eogp.reject_append_only_mutation();

CREATE TRIGGER booking_inquiry_assignment_history_append_only
BEFORE UPDATE OR DELETE ON eogp.booking_inquiry_assignment_history
FOR EACH ROW EXECUTE FUNCTION eogp.reject_append_only_mutation();

CREATE TRIGGER booking_inquiry_annotations_append_only
BEFORE UPDATE OR DELETE ON eogp.booking_inquiry_annotations
FOR EACH ROW EXECUTE FUNCTION eogp.reject_append_only_mutation();

REVOKE ALL ON
  eogp.booking_inquiries,
  eogp.booking_inquiry_attachments,
  eogp.booking_inquiry_annotations,
  eogp.booking_inquiry_status_history,
  eogp.booking_inquiry_assignment_history
FROM PUBLIC, eventor_runtime, eventor_worker, eventor_auth;

CREATE FUNCTION eogp.assert_booking_inquiry_permission(
  p_organization_id uuid,
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

  SELECT status INTO v_membership_status
    FROM eogp.organization_memberships
   WHERE organization_id = p_organization_id
     AND id = p_actor_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_membership_status <> 'active' THEN
    RAISE EXCEPTION 'active organization membership is required' USING ERRCODE = '42501';
  END IF;

  -- Inquiries are not bookings yet, so only organization-wide grants apply.
  -- A booking-scoped grant becomes meaningful only after draft/booking linkage.
  PERFORM 1
    FROM eogp.user_role_grants AS user_grant
    JOIN eogp.role_permissions AS role_permission
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
    RAISE EXCEPTION 'required booking inquiry permission is not granted'
      USING ERRCODE = '42501';
  END IF;
END;
$function$;

CREATE FUNCTION eogp.list_booking_inquiries(
  p_organization_id uuid,
  p_actor_membership_id uuid,
  p_status text DEFAULT NULL,
  p_assigned_to_membership_id uuid DEFAULT NULL,
  p_limit integer DEFAULT 25,
  p_offset integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_total integer;
  v_items jsonb;
BEGIN
  PERFORM eogp.assert_booking_inquiry_permission(
    p_organization_id, p_actor_membership_id, 'booking.inquiry.read'
  );

  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
     OR p_offset IS NULL OR p_offset NOT BETWEEN 0 AND 10000
     OR (p_status IS NOT NULL AND p_status NOT IN
       ('received','under_review','converted','declined','withdrawn','spam')) THEN
    RAISE EXCEPTION 'invalid booking inquiry list filter or pagination'
      USING ERRCODE = '22023';
  END IF;

  IF p_assigned_to_membership_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM eogp.organization_memberships membership
     WHERE membership.organization_id = p_organization_id
       AND membership.id = p_assigned_to_membership_id
       AND membership.status = 'active'
  ) THEN
    RAISE EXCEPTION 'assigned membership is not active in this organization'
      USING ERRCODE = '22023';
  END IF;

  SELECT count(*)::integer INTO v_total
    FROM eogp.booking_inquiries inquiry
   WHERE inquiry.organization_id = p_organization_id
     AND (p_status IS NULL OR inquiry.status = p_status)
     AND (p_assigned_to_membership_id IS NULL
          OR inquiry.assigned_to_membership_id = p_assigned_to_membership_id);

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'inquiryId', page.id,
    'publicReference', page.public_reference,
    'status', page.status,
    'formRevisionId', page.form_revision_id,
    'requesterNameCiphertextBase64', encode(page.requester_name_ciphertext,'base64'),
    'requestedStart', page.requested_start,
    'requestedEnd', page.requested_end,
    'requestedTimezone', page.requested_timezone,
    'assignedToMembershipId', page.assigned_to_membership_id,
    'submittedAt', page.submitted_at,
    'updatedAt', page.updated_at
  ) ORDER BY page.submitted_at DESC, page.id), '[]'::jsonb)
    INTO v_items
    FROM (
      SELECT inquiry.*
        FROM eogp.booking_inquiries inquiry
       WHERE inquiry.organization_id = p_organization_id
         AND (p_status IS NULL OR inquiry.status = p_status)
         AND (p_assigned_to_membership_id IS NULL
              OR inquiry.assigned_to_membership_id = p_assigned_to_membership_id)
       ORDER BY inquiry.submitted_at DESC, inquiry.id
       LIMIT p_limit OFFSET p_offset
    ) page;

  RETURN jsonb_build_object(
    'items', v_items,
    'page', jsonb_build_object('limit',p_limit,'offset',p_offset,'total',v_total)
  );
END;
$function$;

CREATE FUNCTION eogp.get_booking_inquiry(
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

CREATE FUNCTION eogp.assign_booking_inquiry(
  p_organization_id uuid,
  p_inquiry_id uuid,
  p_actor_membership_id uuid,
  p_assigned_to_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_previous_assignee uuid;
BEGIN
  PERFORM eogp.assert_booking_inquiry_permission(
    p_organization_id, p_actor_membership_id, 'booking.inquiry.assign'
  );

  IF p_assigned_to_membership_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM eogp.organization_memberships membership
     WHERE membership.organization_id = p_organization_id
       AND membership.id = p_assigned_to_membership_id
       AND membership.status = 'active'
  ) THEN
    RAISE EXCEPTION 'assignee must be an active member of this organization'
      USING ERRCODE = '22023';
  END IF;

  SELECT assigned_to_membership_id INTO v_previous_assignee
    FROM eogp.booking_inquiries
   WHERE organization_id = p_organization_id
     AND id = p_inquiry_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking inquiry not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_previous_assignee IS NOT DISTINCT FROM p_assigned_to_membership_id THEN
    RETURN jsonb_build_object(
      'inquiryId',p_inquiry_id,
      'assignedToMembershipId',p_assigned_to_membership_id,
      'changed',false
    );
  END IF;

  UPDATE eogp.booking_inquiries
     SET assigned_to_membership_id = p_assigned_to_membership_id,
         updated_at = clock_timestamp()
   WHERE organization_id = p_organization_id
     AND id = p_inquiry_id;

  INSERT INTO eogp.booking_inquiry_assignment_history (
    organization_id,inquiry_id,previous_assignee_membership_id,
    new_assignee_membership_id,actor_membership_id
  ) VALUES (
    p_organization_id,p_inquiry_id,v_previous_assignee,
    p_assigned_to_membership_id,p_actor_membership_id
  );

  INSERT INTO eogp.audit_events (
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.inquiry.assigned','booking_inquiry',p_inquiry_id,
    jsonb_build_object('assignedToMembershipId',p_assigned_to_membership_id)
  );

  RETURN jsonb_build_object(
    'inquiryId',p_inquiry_id,
    'assignedToMembershipId',p_assigned_to_membership_id,
    'changed',true
  );
END;
$function$;

CREATE FUNCTION eogp.change_booking_inquiry_status(
  p_organization_id uuid,
  p_inquiry_id uuid,
  p_actor_membership_id uuid,
  p_new_status text,
  p_reason text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_previous_status text;
BEGIN
  PERFORM eogp.assert_booking_inquiry_permission(
    p_organization_id, p_actor_membership_id, 'booking.inquiry.manage'
  );

  IF p_new_status IS NULL OR p_new_status NOT IN
     ('received','under_review','declined','spam')
     OR nullif(btrim(p_reason),'') IS NULL
     OR length(p_reason) > 1000 THEN
    RAISE EXCEPTION 'invalid booking inquiry status or reason' USING ERRCODE = '22023';
  END IF;

  SELECT status INTO v_previous_status
    FROM eogp.booking_inquiries
   WHERE organization_id = p_organization_id
     AND id = p_inquiry_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking inquiry not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_previous_status = p_new_status THEN
    RETURN jsonb_build_object(
      'inquiryId',p_inquiry_id,
      'previousStatus',v_previous_status,
      'status',p_new_status,
      'changed',false
    );
  END IF;

  IF v_previous_status NOT IN ('received','under_review')
     OR (p_new_status = 'received' AND v_previous_status <> 'under_review')
     OR (p_new_status = 'under_review' AND v_previous_status <> 'received')
     OR (p_new_status IN ('declined','spam') AND v_previous_status NOT IN ('received','under_review')) THEN
    RAISE EXCEPTION 'booking inquiry cannot transition from % to %',
      v_previous_status,p_new_status USING ERRCODE = '55000';
  END IF;

  UPDATE eogp.booking_inquiries
     SET status = p_new_status,
         updated_at = clock_timestamp()
   WHERE organization_id = p_organization_id
     AND id = p_inquiry_id;

  INSERT INTO eogp.booking_inquiry_status_history (
    organization_id,inquiry_id,previous_status,new_status,
    reason,actor_kind,actor_membership_id
  ) VALUES (
    p_organization_id,p_inquiry_id,v_previous_status,p_new_status,
    btrim(p_reason),'membership',p_actor_membership_id
  );

  INSERT INTO eogp.audit_events (
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.inquiry.status_changed','booking_inquiry',p_inquiry_id,
    'booking_inquiry_' || p_new_status,
    jsonb_build_object('previousStatus',v_previous_status,'newStatus',p_new_status)
  );

  RETURN jsonb_build_object(
    'inquiryId',p_inquiry_id,
    'previousStatus',v_previous_status,
    'status',p_new_status,
    'changed',true
  );
END;
$function$;

CREATE FUNCTION eogp.add_booking_inquiry_annotation(
  p_organization_id uuid,
  p_inquiry_id uuid,
  p_actor_membership_id uuid,
  p_annotation text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_annotation_id uuid := gen_random_uuid();
BEGIN
  PERFORM eogp.assert_booking_inquiry_permission(
    p_organization_id, p_actor_membership_id, 'booking.inquiry.annotate'
  );

  IF nullif(btrim(p_annotation),'') IS NULL OR length(p_annotation) > 4000 THEN
    RAISE EXCEPTION 'internal inquiry annotation must contain 1 to 4000 characters'
      USING ERRCODE = '22023';
  END IF;

  PERFORM 1 FROM eogp.booking_inquiries
   WHERE organization_id = p_organization_id
     AND id = p_inquiry_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking inquiry not found' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO eogp.booking_inquiry_annotations (
    id,organization_id,inquiry_id,actor_membership_id,annotation,visibility
  ) VALUES (
    v_annotation_id,p_organization_id,p_inquiry_id,p_actor_membership_id,
    btrim(p_annotation),'internal'
  );

  INSERT INTO eogp.audit_events (
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.inquiry.annotation_added','booking_inquiry',p_inquiry_id,
    jsonb_build_object('annotationId',v_annotation_id,'visibility','internal')
  );

  RETURN jsonb_build_object(
    'annotationId',v_annotation_id,
    'inquiryId',p_inquiry_id,
    'visibility','internal',
    'createdAt',clock_timestamp()
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.assert_booking_inquiry_permission(uuid,uuid,text)
  FROM PUBLIC, eventor_runtime, eventor_worker, eventor_auth;
REVOKE ALL ON FUNCTION eogp.list_booking_inquiries(uuid,uuid,text,uuid,integer,integer)
  FROM PUBLIC, eventor_worker, eventor_auth;
REVOKE ALL ON FUNCTION eogp.get_booking_inquiry(uuid,uuid,uuid)
  FROM PUBLIC, eventor_worker, eventor_auth;
REVOKE ALL ON FUNCTION eogp.assign_booking_inquiry(uuid,uuid,uuid,uuid)
  FROM PUBLIC, eventor_worker, eventor_auth;
REVOKE ALL ON FUNCTION eogp.change_booking_inquiry_status(uuid,uuid,uuid,text,text)
  FROM PUBLIC, eventor_worker, eventor_auth;
REVOKE ALL ON FUNCTION eogp.add_booking_inquiry_annotation(uuid,uuid,uuid,text)
  FROM PUBLIC, eventor_worker, eventor_auth;

GRANT EXECUTE ON FUNCTION eogp.list_booking_inquiries(uuid,uuid,text,uuid,integer,integer),
  eogp.get_booking_inquiry(uuid,uuid,uuid),
  eogp.assign_booking_inquiry(uuid,uuid,uuid,uuid),
  eogp.change_booking_inquiry_status(uuid,uuid,uuid,text,text),
  eogp.add_booking_inquiry_annotation(uuid,uuid,uuid,text)
TO eventor_runtime;
