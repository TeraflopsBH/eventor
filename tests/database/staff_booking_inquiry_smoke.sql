\set ON_ERROR_STOP on

BEGIN;
SET LOCAL ROLE eventor_owner;

SELECT set_config('app.organization_id','a7000000-0000-4000-8000-000000000001',true);
INSERT INTO eogp.organizations (id,slug,name,status,default_timezone)
VALUES (
  'a7000000-0000-4000-8000-000000000001',
  'ci-staff-inquiry',
  'CI Staff Inquiry Organization',
  'active',
  'Europe/Sarajevo'
);

INSERT INTO eogp.users (id,email,display_name,status)
VALUES
  ('a7100000-0000-4000-8000-000000000001','inquiry-owner@example.test','Inquiry Owner','active'),
  ('a7100000-0000-4000-8000-000000000002','inquiry-assignee@example.test','Inquiry Assignee','active'),
  ('a7100000-0000-4000-8000-000000000003','inquiry-unprivileged@example.test','Inquiry Unprivileged','active'),
  ('a7100000-0000-4000-8000-000000000004','other-org@example.test','Other Organization Member','active');

INSERT INTO eogp.organization_memberships (
  id,organization_id,user_id,status,joined_at
) VALUES
  ('a7200000-0000-4000-8000-000000000001','a7000000-0000-4000-8000-000000000001','a7100000-0000-4000-8000-000000000001','active',clock_timestamp()),
  ('a7200000-0000-4000-8000-000000000002','a7000000-0000-4000-8000-000000000001','a7100000-0000-4000-8000-000000000002','active',clock_timestamp()),
  ('a7200000-0000-4000-8000-000000000003','a7000000-0000-4000-8000-000000000001','a7100000-0000-4000-8000-000000000003','active',clock_timestamp());

SELECT set_config('app.organization_id','a7000000-0000-4000-8000-000000000002',true);
INSERT INTO eogp.organizations (id,slug,name,status,default_timezone)
VALUES (
  'a7000000-0000-4000-8000-000000000002',
  'ci-other-inquiry-tenant',
  'CI Other Inquiry Tenant',
  'active',
  'Europe/Sarajevo'
);
INSERT INTO eogp.organization_memberships (
  id,organization_id,user_id,status,joined_at
) VALUES (
  'a7200000-0000-4000-8000-000000000004',
  'a7000000-0000-4000-8000-000000000002',
  'a7100000-0000-4000-8000-000000000004',
  'active',
  clock_timestamp()
);

SELECT set_config('app.organization_id','a7000000-0000-4000-8000-000000000001',true);

INSERT INTO eogp.roles (id,organization_id,code,name,scope_kind)
VALUES (
  'a7300000-0000-4000-8000-000000000001',
  'a7000000-0000-4000-8000-000000000001',
  'inquiry-operator',
  'Inquiry Operator',
  'organization'
);

INSERT INTO eogp.role_permissions (organization_id,role_id,permission_code)
VALUES
  ('a7000000-0000-4000-8000-000000000001','a7300000-0000-4000-8000-000000000001','booking.inquiry.read'),
  ('a7000000-0000-4000-8000-000000000001','a7300000-0000-4000-8000-000000000001','booking.inquiry.assign'),
  ('a7000000-0000-4000-8000-000000000001','a7300000-0000-4000-8000-000000000001','booking.inquiry.manage'),
  ('a7000000-0000-4000-8000-000000000001','a7300000-0000-4000-8000-000000000001','booking.inquiry.annotate'),
  ('a7000000-0000-4000-8000-000000000001','a7300000-0000-4000-8000-000000000001','booking.inquiry.convert'),
  ('a7000000-0000-4000-8000-000000000001','a7300000-0000-4000-8000-000000000001','booking.draft.read'),
  ('a7000000-0000-4000-8000-000000000001','a7300000-0000-4000-8000-000000000001','booking.draft.manage');

INSERT INTO eogp.roles (id,organization_id,code,name,scope_kind)
VALUES (
  'a7300000-0000-4000-8000-000000000002',
  'a7000000-0000-4000-8000-000000000001',
  'inquiry-reader',
  'Inquiry Reader',
  'organization'
);
INSERT INTO eogp.role_permissions (organization_id,role_id,permission_code)
VALUES (
  'a7000000-0000-4000-8000-000000000001',
  'a7300000-0000-4000-8000-000000000002',
  'booking.inquiry.read'
);
INSERT INTO eogp.user_role_grants (
  organization_id,membership_id,role_id,scope_kind,granted_by_membership_id
) VALUES (
  'a7000000-0000-4000-8000-000000000001',
  'a7200000-0000-4000-8000-000000000002',
  'a7300000-0000-4000-8000-000000000002',
  'organization',
  'a7200000-0000-4000-8000-000000000001'
);

INSERT INTO eogp.user_role_grants (
  organization_id,membership_id,role_id,scope_kind,granted_by_membership_id
) VALUES (
  'a7000000-0000-4000-8000-000000000001',
  'a7200000-0000-4000-8000-000000000001',
  'a7300000-0000-4000-8000-000000000001',
  'organization',
  'a7200000-0000-4000-8000-000000000001'
);

INSERT INTO eogp.booking_form_definitions (
  id,organization_id,scope_kind,form_code,name,status
) VALUES (
  'a7400000-0000-4000-8000-000000000001',
  'a7000000-0000-4000-8000-000000000001',
  'organization',
  'venue-rental',
  'Venue rental inquiry',
  'active'
);

INSERT INTO eogp.booking_form_revisions (
  id,organization_id,form_definition_id,revision_number,locale,
  field_schema,state,published_at
) VALUES (
  'a7500000-0000-4000-8000-000000000001',
  'a7000000-0000-4000-8000-000000000001',
  'a7400000-0000-4000-8000-000000000001',
  1,
  'bs-BA',
  '{"fields":[{"code":"event_date","type":"date","required":true}]}'::jsonb,
  'published',
  clock_timestamp()
);

DO $test$
DECLARE
  v_submitted jsonb;
  v_inquiry_id uuid;
  v_public_reference text;
  v_list jsonb;
  v_capabilities jsonb;
  v_assignee_list jsonb;
  v_assignee_denied boolean := false;
  v_detail jsonb;
  v_assigned jsonb;
  v_status jsonb;
  v_annotation jsonb;
  v_conversion_submitted jsonb;
  v_conversion_inquiry_id uuid;
  v_conversion jsonb;
  v_conversion_replay jsonb;
  v_converted_detail jsonb;
  v_draft_detail jsonb;
  v_new_revision jsonb;
  v_stale_revision_denied boolean := false;
  v_draft_read_denied boolean := false;
  v_conversion_denied boolean := false;
  v_denied boolean := false;
  v_cross_tenant_denied boolean := false;
  v_invalid_transition_denied boolean := false;
  v_terminal_assignment_denied boolean := false;
  v_terminal_conversion_denied boolean := false;
  v_append_only_denied boolean := false;
  v_ciphertext bytea := decode('45435031' || repeat('00',29),'hex');
BEGIN
  v_submitted := eogp.submit_public_booking_inquiry(
    'ci-staff-inquiry',
    'venue-rental',
    'a7500000-0000-4000-8000-000000000001',
    repeat('a',64),
    repeat('b',64),
    repeat('c',64),
    v_ciphertext,
    v_ciphertext,
    NULL,NULL,NULL,NULL,
    '2027-01-18 09:00:00+01',
    '2027-01-18 12:00:00+01',
    'Europe/Sarajevo'
  );

  v_inquiry_id := (v_submitted->>'inquiryId')::uuid;
  v_public_reference := v_submitted->>'publicReference';

  v_list := eogp.list_booking_inquiries(
    'a7000000-0000-4000-8000-000000000001',
    'a7200000-0000-4000-8000-000000000001',
    'received',NULL,10,0
  );
  IF jsonb_array_length(v_list->'items') <> 1
     OR v_list->'items'->0->>'inquiryId' <> v_inquiry_id::text
     OR v_list->'items'->0->>'publicReference' <> v_public_reference
     OR v_list->'page'->>'total' <> '1' THEN
    RAISE EXCEPTION 'permission-filtered booking inquiry inbox did not return the submitted inquiry: %',v_list;
  END IF;

  v_capabilities := eogp.get_booking_inquiry_capabilities(
    'a7000000-0000-4000-8000-000000000001',
    'a7200000-0000-4000-8000-000000000001'
  );
  IF v_capabilities->>'canAssign' IS DISTINCT FROM 'true'
     OR v_capabilities->>'canManage' IS DISTINCT FROM 'true'
     OR v_capabilities->>'canAnnotate' IS DISTINCT FROM 'true'
     OR v_capabilities->>'canConvert' IS DISTINCT FROM 'true'
     OR v_capabilities->>'canReadDraft' IS DISTINCT FROM 'true'
     OR v_capabilities->>'canManageDraft' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'inquiry capabilities projection did not reflect the granted permissions: %',v_capabilities;
  END IF;

  v_assignee_list := eogp.list_booking_inquiry_assignees(
    'a7000000-0000-4000-8000-000000000001',
    'a7200000-0000-4000-8000-000000000001'
  );
  IF jsonb_array_length(v_assignee_list->'items') <> 3
     OR NOT EXISTS (
       SELECT 1 FROM jsonb_array_elements(v_assignee_list->'items') item
        WHERE item->>'membershipId' = 'a7200000-0000-4000-8000-000000000002'
          AND item->>'displayName' = 'Inquiry Assignee'
     ) OR v_assignee_list::text ILIKE '%@example.test%' THEN
    RAISE EXCEPTION 'permissioned inquiry assignee roster did not return active members only or exposed contact data: %',v_assignee_list;
  END IF;

  BEGIN
    PERFORM eogp.list_booking_inquiry_assignees(
      'a7000000-0000-4000-8000-000000000001',
      'a7200000-0000-4000-8000-000000000003'
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_assignee_denied := true;
  END;
  IF NOT v_assignee_denied THEN
    RAISE EXCEPTION 'membership without inquiry assignment permission accessed the assignee roster';
  END IF;

  v_detail := eogp.get_booking_inquiry(
    'a7000000-0000-4000-8000-000000000001',
    v_inquiry_id,
    'a7200000-0000-4000-8000-000000000001'
  );
  IF v_detail->>'status' <> 'received'
     OR v_detail->'fieldSchema'->'fields'->0->>'code' <> 'event_date'
     OR jsonb_array_length(v_detail->'statusHistory') <> 1
     OR v_detail->'statusHistory'->0->>'actorKind' <> 'public' THEN
    RAISE EXCEPTION 'booking inquiry detail or initial status history was incomplete: %',v_detail;
  END IF;

  v_assigned := eogp.assign_booking_inquiry(
    'a7000000-0000-4000-8000-000000000001',
    v_inquiry_id,
    'a7200000-0000-4000-8000-000000000001',
    'a7200000-0000-4000-8000-000000000002'
  );
  IF v_assigned->>'changed' <> 'true'
     OR v_assigned->>'assignedToMembershipId' <> 'a7200000-0000-4000-8000-000000000002' THEN
    RAISE EXCEPTION 'inquiry assignment command returned an unexpected result: %',v_assigned;
  END IF;

  v_status := eogp.change_booking_inquiry_status(
    'a7000000-0000-4000-8000-000000000001',
    v_inquiry_id,
    'a7200000-0000-4000-8000-000000000001',
    'under_review',
    'Assigned to the booking team.'
  );
  IF v_status->>'status' <> 'under_review' OR v_status->>'changed' <> 'true' THEN
    RAISE EXCEPTION 'inquiry status command returned an unexpected result: %',v_status;
  END IF;

  v_annotation := eogp.add_booking_inquiry_annotation(
    'a7000000-0000-4000-8000-000000000001',
    v_inquiry_id,
    'a7200000-0000-4000-8000-000000000001',
    'Call to confirm setup access.'
  );
  IF v_annotation->>'visibility' <> 'internal' THEN
    RAISE EXCEPTION 'inquiry annotation was not stored as internal: %',v_annotation;
  END IF;

  v_detail := eogp.get_booking_inquiry(
    'a7000000-0000-4000-8000-000000000001',
    v_inquiry_id,
    'a7200000-0000-4000-8000-000000000001'
  );
  IF v_detail->>'assignedToMembershipId' <> 'a7200000-0000-4000-8000-000000000002'
     OR v_detail->>'status' <> 'under_review'
     OR jsonb_array_length(v_detail->'statusHistory') <> 2
     OR jsonb_array_length(v_detail->'assignmentHistory') <> 1
     OR jsonb_array_length(v_detail->'annotations') <> 1 THEN
    RAISE EXCEPTION 'booking inquiry history projections did not reflect the commands: %',v_detail;
  END IF;

  -- Use a second inquiry to verify conversion independently from the
  -- assignment/status/terminal-state tests above.
  v_conversion_submitted := eogp.submit_public_booking_inquiry(
    'ci-staff-inquiry',
    'venue-rental',
    'a7500000-0000-4000-8000-000000000001',
    repeat('d',64),
    repeat('e',64),
    repeat('f',64),
    v_ciphertext,
    v_ciphertext,
    NULL,NULL,NULL,NULL,
    '2027-01-19 09:00:00+01',
    '2027-01-19 12:00:00+01',
    'Europe/Sarajevo'
  );
  v_conversion_inquiry_id := (v_conversion_submitted->>'inquiryId')::uuid;

  BEGIN
    PERFORM eogp.convert_booking_inquiry_to_draft(
      'a7000000-0000-4000-8000-000000000001',
      v_conversion_inquiry_id,
      'a7200000-0000-4000-8000-000000000003'
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_conversion_denied := true;
  END;
  IF NOT v_conversion_denied THEN
    RAISE EXCEPTION 'membership without inquiry conversion permission converted an inquiry';
  END IF;

  v_conversion := eogp.convert_booking_inquiry_to_draft(
    'a7000000-0000-4000-8000-000000000001',
    v_conversion_inquiry_id,
    'a7200000-0000-4000-8000-000000000001'
  );
  IF v_conversion->>'status' <> 'converted'
     OR v_conversion->>'changed' <> 'true'
     OR v_conversion->>'revisionNumber' <> '1'
     OR v_conversion->>'draftId' IS NULL
     OR v_conversion->>'revisionId' IS NULL THEN
    RAISE EXCEPTION 'inquiry conversion did not create draft revision 1: %',v_conversion;
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM eogp.booking_drafts draft
      JOIN eogp.booking_draft_revisions revision
        ON revision.organization_id = draft.organization_id
       AND revision.draft_id = draft.id
       AND revision.revision_number = 1
     WHERE draft.organization_id = 'a7000000-0000-4000-8000-000000000001'
       AND draft.id = (v_conversion->>'draftId')::uuid
       AND draft.source_inquiry_id = v_conversion_inquiry_id
       AND draft.status = 'draft'
       AND draft.current_revision_number = 1
       AND revision.id = (v_conversion->>'revisionId')::uuid
       AND revision.source_form_revision_id = 'a7500000-0000-4000-8000-000000000001'
       AND revision.requested_start = '2027-01-19 09:00:00+01'::timestamptz
       AND revision.requested_end = '2027-01-19 12:00:00+01'::timestamptz
       AND revision.timezone_name = 'Europe/Sarajevo'
       AND revision.values_snapshot->>'encryption' = 'ECP1'
       AND revision.values_snapshot->>'contactKind' = 'other'
       AND revision.values_snapshot->>'ciphertextBase64' = encode(v_ciphertext,'base64')
       AND revision.values_snapshot->>'schemaVersion' = '1'
  ) THEN
    RAISE EXCEPTION 'draft revision did not preserve the source inquiry metadata and encrypted submission';
  END IF;

  IF (SELECT status FROM eogp.booking_inquiries
       WHERE organization_id='a7000000-0000-4000-8000-000000000001'
         AND id=v_conversion_inquiry_id) <> 'converted' THEN
    RAISE EXCEPTION 'source inquiry status was not converted';
  END IF;

  v_converted_detail := eogp.get_booking_inquiry(
    'a7000000-0000-4000-8000-000000000001',
    v_conversion_inquiry_id,
    'a7200000-0000-4000-8000-000000000001'
  );
  IF v_converted_detail->>'status' <> 'converted'
     OR jsonb_array_length(v_converted_detail->'statusHistory') <> 2
     OR NOT EXISTS (
       SELECT 1
         FROM jsonb_array_elements(v_converted_detail->'statusHistory') history
        WHERE history->>'newStatus' = 'converted'
          AND history->>'actorKind' = 'membership'
     ) THEN
    RAISE EXCEPTION 'conversion did not append the attributed inquiry status history: %',v_converted_detail;
  END IF;

  v_conversion_replay := eogp.convert_booking_inquiry_to_draft(
    'a7000000-0000-4000-8000-000000000001',
    v_conversion_inquiry_id,
    'a7200000-0000-4000-8000-000000000001'
  );
  IF v_conversion_replay->>'changed' <> 'false'
     OR v_conversion_replay->>'draftId' <> v_conversion->>'draftId'
     OR v_conversion_replay->>'revisionId' <> v_conversion->>'revisionId'
     OR (SELECT count(*) FROM eogp.booking_draft_revisions
          WHERE organization_id='a7000000-0000-4000-8000-000000000001'
            AND draft_id=(v_conversion->>'draftId')::uuid) <> 1 THEN
    RAISE EXCEPTION 'replayed inquiry conversion created duplicate draft state: %',v_conversion_replay;
  END IF;

  IF (SELECT count(*) FROM eogp.audit_events
       WHERE organization_id='a7000000-0000-4000-8000-000000000001'
         AND actor_membership_id='a7200000-0000-4000-8000-000000000001'
         AND action='booking.inquiry.converted'
         AND aggregate_type='booking_inquiry'
         AND aggregate_id=v_conversion_inquiry_id
         AND safe_metadata->>'draftId'=v_conversion->>'draftId') <> 1 THEN
    RAISE EXCEPTION 'conversion audit event was missing, duplicated or incorrectly attributed';
  END IF;

  -- Draft access requires a dedicated organization-scope grant; inquiry
  -- read/convert permission alone does not imply draft access.
  BEGIN
    PERFORM eogp.get_booking_draft(
      'a7000000-0000-4000-8000-000000000001',
      (v_conversion->>'draftId')::uuid,
      'a7200000-0000-4000-8000-000000000003'
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_draft_read_denied := true;
  END;
  IF NOT v_draft_read_denied THEN
    RAISE EXCEPTION 'membership without booking draft permission read a booking draft';
  END IF;

  v_converted_detail := eogp.get_booking_inquiry(
    'a7000000-0000-4000-8000-000000000001',
    v_conversion_inquiry_id,
    'a7200000-0000-4000-8000-000000000002'
  );
  IF v_converted_detail->'bookingDraft' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'inquiry-only reader was shown a booking draft reference without draft permission: %',v_converted_detail->'bookingDraft';
  END IF;

    v_draft_detail := eogp.get_booking_draft(
    'a7000000-0000-4000-8000-000000000001',
    (v_conversion->>'draftId')::uuid,
    'a7200000-0000-4000-8000-000000000001'
  );
  IF v_draft_detail->>'draftId' <> v_conversion->>'draftId'
     OR v_draft_detail->>'status' <> 'draft'
     OR v_draft_detail->>'currentRevisionNumber' <> '1'
     OR v_draft_detail->'currentRevision'->>'revisionNumber' <> '1'
     OR v_draft_detail->'currentRevision'->>'sourceFormRevisionId' <> 'a7500000-0000-4000-8000-000000000001'
     OR v_draft_detail->'currentRevision'->'fieldSchema'->'fields'->0->>'code' <> 'event_date'
     OR v_draft_detail->'currentRevision'->'fieldSchema'->'fields'->0->>'type' <> 'date'
     OR v_draft_detail->'currentRevision'->'valuesSnapshot'->>'encryption' <> 'ECP1'
     OR v_draft_detail->'currentRevision'->'valuesSnapshot'->>'ciphertextBase64' <> encode(v_ciphertext,'base64')
     OR jsonb_array_length(v_draft_detail->'revisionHistory') <> 1 THEN
    RAISE EXCEPTION 'permission-checked draft projection did not return the initial encrypted revision: %',v_draft_detail;
  END IF;

  v_new_revision := eogp.create_booking_draft_revision(
    'a7000000-0000-4000-8000-000000000001',
    (v_conversion->>'draftId')::uuid,
    'a7200000-0000-4000-8000-000000000001',
    1,
    v_ciphertext,
    '2027-01-19 09:00:00+01',
    '2027-01-19 13:00:00+01',
    'Europe/Sarajevo',
    '[]'::jsonb,
    '[]'::jsonb,
    'Updated requested end time after follow-up with requester.'
  );
  IF v_new_revision->>'revisionNumber' <> '2'
     OR v_new_revision->>'previousRevisionNumber' <> '1'
     OR v_new_revision->>'status' <> 'draft'
     OR v_new_revision->>'changed' <> 'true' THEN
    RAISE EXCEPTION 'draft successor revision command returned an unexpected result: %',v_new_revision;
  END IF;

  IF (SELECT current_revision_number FROM eogp.booking_drafts
       WHERE organization_id='a7000000-0000-4000-8000-000000000001'
         AND id=(v_conversion->>'draftId')::uuid) <> 2
     OR (SELECT requested_end FROM eogp.booking_draft_revisions
          WHERE organization_id='a7000000-0000-4000-8000-000000000001'
            AND draft_id=(v_conversion->>'draftId')::uuid
            AND revision_number=1) <> '2027-01-19 12:00:00+01'::timestamptz
     OR (SELECT requested_end FROM eogp.booking_draft_revisions
          WHERE organization_id='a7000000-0000-4000-8000-000000000001'
            AND draft_id=(v_conversion->>'draftId')::uuid
            AND revision_number=2) <> '2027-01-19 13:00:00+01'::timestamptz
     OR (SELECT count(*) FROM eogp.booking_draft_revisions
          WHERE organization_id='a7000000-0000-4000-8000-000000000001'
            AND draft_id=(v_conversion->>'draftId')::uuid) <> 2 THEN
    RAISE EXCEPTION 'draft successor revision modified or lost its immutable predecessor';
  END IF;

  v_draft_detail := eogp.get_booking_draft(
    'a7000000-0000-4000-8000-000000000001',
    (v_conversion->>'draftId')::uuid,
    'a7200000-0000-4000-8000-000000000001'
  );
  IF v_draft_detail->>'currentRevisionNumber' <> '2'
     OR v_draft_detail->'currentRevision'->>'revisionId' <> v_new_revision->>'revisionId'
     OR jsonb_array_length(v_draft_detail->'revisionHistory') <> 2
     OR v_draft_detail->'currentRevision'->>'sourceFormRevisionId' <> 'a7500000-0000-4000-8000-000000000001'
     OR v_draft_detail->'currentRevision'->'valuesSnapshot'->>'ciphertextBase64' <> encode(v_ciphertext,'base64') THEN
    RAISE EXCEPTION 'draft projection did not return successor revision and full revision history: %',v_draft_detail;
  END IF;

  BEGIN
    PERFORM eogp.create_booking_draft_revision(
      'a7000000-0000-4000-8000-000000000001',
      (v_conversion->>'draftId')::uuid,
      'a7200000-0000-4000-8000-000000000001',
      1,
      v_ciphertext,
      '2027-01-19 09:00:00+01',
      '2027-01-19 14:00:00+01',
      'Europe/Sarajevo',
      '[]'::jsonb,
      '[]'::jsonb,
      'Attempt stale revision write.'
    );
  EXCEPTION WHEN SQLSTATE '40001' THEN
    v_stale_revision_denied := true;
  END;
  IF NOT v_stale_revision_denied THEN
    RAISE EXCEPTION 'draft revision command accepted a stale expected revision number';
  END IF;

  IF (SELECT count(*) FROM eogp.audit_events
       WHERE organization_id='a7000000-0000-4000-8000-000000000001'
         AND actor_membership_id='a7200000-0000-4000-8000-000000000001'
         AND action='booking.draft.revised'
         AND aggregate_type='booking_draft'
         AND aggregate_id=(v_conversion->>'draftId')::uuid
         AND safe_metadata->>'revisionId'=v_new_revision->>'revisionId') <> 1 THEN
    RAISE EXCEPTION 'draft successor revision audit event was missing, duplicated or incorrectly attributed';
  END IF;

  IF EXISTS (
    SELECT 1 FROM eogp.booking_offers offer
     WHERE offer.organization_id='a7000000-0000-4000-8000-000000000001'
       AND offer.draft_id=(v_conversion->>'draftId')::uuid
  ) THEN
    RAISE EXCEPTION 'inquiry conversion unexpectedly created an offer';
  END IF;

  BEGIN
    UPDATE eogp.booking_inquiry_status_history
       SET reason='attempted history mutation'
     WHERE organization_id='a7000000-0000-4000-8000-000000000001'
       AND inquiry_id=v_inquiry_id
       AND new_status='under_review';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_append_only_denied := true;
  END;
  IF NOT v_append_only_denied THEN
    RAISE EXCEPTION 'inquiry status history was mutable';
  END IF;

  PERFORM eogp.change_booking_inquiry_status(
    'a7000000-0000-4000-8000-000000000001',
    v_inquiry_id,
    'a7200000-0000-4000-8000-000000000001',
    'declined',
    'Venue unavailable for requested dates.'
  );

  BEGIN
    PERFORM eogp.change_booking_inquiry_status(
      'a7000000-0000-4000-8000-000000000001',
      v_inquiry_id,
      'a7200000-0000-4000-8000-000000000001',
      'under_review',
      'Attempt to reopen a terminal inquiry.'
    );
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_invalid_transition_denied := true;
  END;
  IF NOT v_invalid_transition_denied THEN
    RAISE EXCEPTION 'terminal inquiry was incorrectly allowed to transition back to review';
  END IF;

  BEGIN
    PERFORM eogp.assign_booking_inquiry(
      'a7000000-0000-4000-8000-000000000001',
      v_inquiry_id,
      'a7200000-0000-4000-8000-000000000001',
      'a7200000-0000-4000-8000-000000000002'
    );
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_terminal_assignment_denied := true;
  END;
  IF NOT v_terminal_assignment_denied THEN
    RAISE EXCEPTION 'terminal inquiry was incorrectly assignable';
  END IF;

  BEGIN
    PERFORM eogp.convert_booking_inquiry_to_draft(
      'a7000000-0000-4000-8000-000000000001',
      v_inquiry_id,
      'a7200000-0000-4000-8000-000000000001'
    );
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_terminal_conversion_denied := true;
  END;
  IF NOT v_terminal_conversion_denied THEN
    RAISE EXCEPTION 'declined inquiry was incorrectly convertible to a booking draft';
  END IF;

  BEGIN
    PERFORM eogp.list_booking_inquiries(
      'a7000000-0000-4000-8000-000000000001',
      'a7200000-0000-4000-8000-000000000003',
      NULL,NULL,10,0
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'membership without inquiry permission accessed the inbox';
  END IF;

  BEGIN
    PERFORM eogp.assign_booking_inquiry(
      'a7000000-0000-4000-8000-000000000001',
      v_inquiry_id,
      'a7200000-0000-4000-8000-000000000001',
      'a7200000-0000-4000-8000-000000000004'
    );
  EXCEPTION WHEN invalid_parameter_value THEN
    v_cross_tenant_denied := true;
  END;
  IF NOT v_cross_tenant_denied THEN
    RAISE EXCEPTION 'inquiry was assignable to a member of another organization';
  END IF;

  IF has_table_privilege('eventor_runtime','eogp.booking_inquiries','SELECT')
     OR has_table_privilege('eventor_runtime','eogp.booking_inquiry_annotations','INSERT')
     OR has_table_privilege('eventor_runtime','eogp.booking_inquiry_status_history','SELECT')
     OR has_table_privilege('eventor_runtime','eogp.booking_inquiry_assignment_history','INSERT')
     OR has_table_privilege('eventor_runtime','eogp.booking_drafts','SELECT')
     OR has_table_privilege('eventor_runtime','eogp.booking_drafts','INSERT')
     OR has_table_privilege('eventor_runtime','eogp.booking_drafts','UPDATE')
     OR has_table_privilege('eventor_runtime','eogp.booking_drafts','DELETE')
     OR has_table_privilege('eventor_runtime','eogp.booking_draft_revisions','SELECT')
     OR has_table_privilege('eventor_runtime','eogp.booking_draft_revisions','INSERT')
     OR has_table_privilege('eventor_runtime','eogp.booking_draft_revisions','UPDATE')
     OR has_table_privilege('eventor_runtime','eogp.booking_draft_revisions','DELETE')
     OR has_table_privilege('eventor_runtime','eogp.booking_draft_space_lines','SELECT')
     OR has_table_privilege('eventor_runtime','eogp.booking_draft_space_lines','INSERT')
     OR has_table_privilege('eventor_runtime','eogp.booking_draft_space_lines','UPDATE')
     OR has_table_privilege('eventor_runtime','eogp.booking_draft_space_lines','DELETE')
     OR has_table_privilege('eventor_runtime','eogp.booking_offers','SELECT')
     OR has_table_privilege('eventor_runtime','eogp.booking_offers','INSERT')
     OR has_table_privilege('eventor_runtime','eogp.booking_offers','UPDATE')
     OR has_table_privilege('eventor_runtime','eogp.booking_offers','DELETE')
     OR has_table_privilege('eventor_runtime','eogp.booking_offer_revisions','SELECT')
     OR has_table_privilege('eventor_runtime','eogp.booking_offer_revisions','INSERT')
     OR has_table_privilege('eventor_runtime','eogp.booking_offer_revisions','UPDATE')
     OR has_table_privilege('eventor_runtime','eogp.booking_offer_revisions','DELETE')
     OR has_table_privilege('eventor_runtime','eogp.booking_resource_lines','SELECT')
     OR has_table_privilege('eventor_runtime','eogp.booking_resource_lines','INSERT')
     OR has_table_privilege('eventor_runtime','eogp.booking_resource_lines','UPDATE')
     OR has_table_privilege('eventor_runtime','eogp.booking_resource_lines','DELETE') THEN
    RAISE EXCEPTION 'runtime role has direct access to protected inquiry or draft source/history tables';
  END IF;

  IF NOT has_function_privilege(
    'eventor_runtime','eogp.list_booking_inquiries(uuid,uuid,text,uuid,integer,integer)','EXECUTE'
  ) OR NOT has_function_privilege(
    'eventor_runtime','eogp.get_booking_inquiry(uuid,uuid,uuid)','EXECUTE'
  ) OR NOT has_function_privilege(
    'eventor_runtime','eogp.list_booking_inquiry_assignees(uuid,uuid)','EXECUTE'
  ) OR NOT has_function_privilege(
    'eventor_runtime','eogp.get_booking_inquiry_capabilities(uuid,uuid)','EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role cannot execute permission-filtered inquiry projections';
  END IF;
  IF has_function_privilege(
    'eventor_runtime','eogp.assert_booking_draft_permission(uuid,uuid,uuid,text)','EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role can call the internal booking draft permission helper directly';
  END IF;

  IF NOT has_function_privilege(
    'eventor_runtime','eogp.convert_booking_inquiry_to_draft(uuid,uuid,uuid)','EXECUTE'
  ) OR NOT has_function_privilege(
    'eventor_runtime','eogp.get_booking_draft(uuid,uuid,uuid)','EXECUTE'
  ) OR NOT has_function_privilege(
    'eventor_runtime','eogp.create_booking_draft_revision(uuid,uuid,uuid,integer,bytea,timestamptz,timestamptz,text,jsonb,jsonb,text)','EXECUTE'
  ) OR NOT has_function_privilege(
    'eventor_runtime','eogp.assign_booking_inquiry(uuid,uuid,uuid,uuid)','EXECUTE'
  ) OR NOT has_function_privilege(
    'eventor_runtime','eogp.change_booking_inquiry_status(uuid,uuid,uuid,text,text)','EXECUTE'
  ) OR NOT has_function_privilege(
    'eventor_runtime','eogp.add_booking_inquiry_annotation(uuid,uuid,uuid,text)','EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role cannot execute the staff inquiry commands';
  END IF;

END;
$test$;

ROLLBACK;
