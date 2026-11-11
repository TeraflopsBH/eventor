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
  ('a7000000-0000-4000-8000-000000000001','a7300000-0000-4000-8000-000000000001','booking.inquiry.annotate');

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
  v_assignee_list jsonb;
  v_assignee_denied boolean := false;
  v_detail jsonb;
  v_assigned jsonb;
  v_status jsonb;
  v_annotation jsonb;
  v_denied boolean := false;
  v_cross_tenant_denied boolean := false;
  v_invalid_transition_denied boolean := false;
  v_terminal_assignment_denied boolean := false;
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

  v_assignee_list := eogp.list_booking_inquiry_assignees(
    'a7000000-0000-4000-8000-000000000001',
    'a7200000-0000-4000-8000-000000000001'
  );
  IF jsonb_array_length(v_assignee_list->'items') <> 3
     OR NOT EXISTS (
       SELECT 1 FROM jsonb_array_elements(v_assignee_list->'items') item
        WHERE item->>'membershipId' = 'a7200000-0000-4000-8000-000000000002'
          AND item->>'displayName' = 'Inquiry Assignee'
     ) THEN
    RAISE EXCEPTION 'permissioned inquiry assignee roster did not return active members only: %',v_assignee_list;
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
     OR has_table_privilege('eventor_runtime','eogp.booking_inquiry_assignment_history','INSERT') THEN
    RAISE EXCEPTION 'runtime role has direct access to protected inquiry source/history tables';
  END IF;

  IF NOT has_function_privilege(
    'eventor_runtime','eogp.list_booking_inquiries(uuid,uuid,text,uuid,integer,integer)','EXECUTE'
  ) OR NOT has_function_privilege(
    'eventor_runtime','eogp.get_booking_inquiry(uuid,uuid,uuid)','EXECUTE'
  ) OR NOT has_function_privilege(
    'eventor_runtime','eogp.list_booking_inquiry_assignees(uuid,uuid)','EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role cannot execute permission-filtered inquiry projections';
  END IF;
  IF NOT has_function_privilege(
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
