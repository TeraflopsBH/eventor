\set ON_ERROR_STOP on

-- Runs as eventor_runtime. Confirms form authoring is available only through
-- tenant-scoped, permission-checked commands and never through direct table DML.
DO $test$
DECLARE
  v_name text;
  v_functions text[] := ARRAY[
    'eogp.get_booking_forms(uuid,uuid)',
    'eogp.create_booking_form(uuid,uuid,text,text,text,jsonb)',
    'eogp.create_booking_form_revision(uuid,uuid,uuid)',
    'eogp.save_booking_form_draft(uuid,uuid,uuid,uuid,text,jsonb)',
    'eogp.publish_booking_form_revision(uuid,uuid,uuid,uuid)'
  ];
BEGIN
  FOREACH v_name IN ARRAY v_functions LOOP
    IF to_regprocedure(v_name) IS NULL THEN
      RAISE EXCEPTION 'required booking-form authoring command % is missing',v_name;
    END IF;
    IF NOT has_function_privilege(current_user,to_regprocedure(v_name),'EXECUTE') THEN
      RAISE EXCEPTION 'runtime role cannot execute booking-form command %',v_name;
    END IF;
  END LOOP;

  IF has_table_privilege(current_user,'eogp.booking_form_definitions','SELECT')
     OR has_table_privilege(current_user,'eogp.booking_form_definitions','INSERT')
     OR has_table_privilege(current_user,'eogp.booking_form_revisions','SELECT')
     OR has_table_privilege(current_user,'eogp.booking_form_revisions','INSERT')
     OR has_table_privilege(current_user,'eogp.booking_form_revisions','UPDATE')
     OR has_table_privilege(current_user,'eogp.booking_form_catalogue_bindings','SELECT')
     OR has_table_privilege(current_user,'eogp.booking_form_catalogue_bindings','INSERT') THEN
    RAISE EXCEPTION 'runtime role has direct access to booking-form authoring tables';
  END IF;

  IF has_function_privilege(current_user,
       'eogp.assert_revision_parent_mutable(text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'runtime role must not execute internal revision guard directly';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    JOIN pg_catalog.pg_class r ON r.oid=t.tgrelid
    JOIN pg_catalog.pg_namespace n ON n.oid=r.relnamespace
    WHERE n.nspname='eogp' AND r.relname='booking_form_revisions'
      AND t.tgname='booking_form_revisions_published_immutable_guard'
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'published booking-form revision immutability guard is missing';
  END IF;
END;
$test$;

\echo 'Booking-form authoring schema smoke tests passed.'
