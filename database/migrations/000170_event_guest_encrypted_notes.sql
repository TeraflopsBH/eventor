INSERT INTO eogp.permissions(code,description,scope_kind,is_sensitive) VALUES
  ('guest.notes.read','Read restricted event guest notes','event',true),
  ('guest.notes.manage','Record and withdraw restricted event guest notes','event',true);

ALTER TABLE eogp.guest_notes
  ADD COLUMN storage_format text,
  ADD COLUMN withdrawn_at timestamptz,
  ADD COLUMN withdrawn_by_membership_id uuid,
  ADD FOREIGN KEY (organization_id,withdrawn_by_membership_id) REFERENCES eogp.organization_memberships(organization_id,id),
  ADD CHECK ((withdrawn_at IS NULL)=(withdrawn_by_membership_id IS NULL)),
  ADD CHECK (storage_format IS NULL OR (
    storage_format='guest-note-v1' AND sensitivity='restricted'
    AND octet_length(note_ciphertext) BETWEEN 33 AND 8032
    AND substring(note_ciphertext from 1 for 4)=convert_to('ECP1','UTF8')
  ));
CREATE INDEX guest_notes_participation_created_idx
  ON eogp.guest_notes(organization_id,event_id,participation_id,created_at DESC,id)
  WHERE storage_format='guest-note-v1';
REVOKE ALL ON eogp.guest_notes FROM PUBLIC,eventor_runtime;

CREATE FUNCTION eogp.assert_event_guest_notes_permission(p_org uuid,p_event uuid,p_actor uuid,p_write boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog,eogp
AS $function$
BEGIN
  IF NOT p_write THEN
    BEGIN
      PERFORM eogp.assert_event_command_permission(p_org,p_event,p_actor,'guest.notes.read');
      RETURN;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END IF;
  PERFORM eogp.assert_event_command_permission(p_org,p_event,p_actor,'guest.notes.manage');
END;
$function$;

CREATE FUNCTION eogp.can_view_event_guest_notes(p_org uuid,p_event uuid,p_actor uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog,eogp
AS $function$
BEGIN
  PERFORM eogp.assert_event_guest_notes_permission(p_org,p_event,p_actor,false);
  RETURN true;
EXCEPTION WHEN insufficient_privilege THEN RETURN false;
END;
$function$;

CREATE FUNCTION eogp.read_event_guest_notes(p_org uuid,p_event uuid,p_actor uuid,p_guest uuid,p_offset integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_event_status text;
  v_guest_status text;
  v_can_manage boolean;
  v_notes jsonb;
BEGIN
  v_can_manage := eogp.assert_event_guest_list_access(p_org,p_event,p_actor);
  PERFORM eogp.assert_event_guest_notes_permission(p_org,p_event,p_actor,false);
  IF coalesce(p_offset,-1) NOT BETWEEN 0 AND 100000 THEN
    RAISE EXCEPTION 'invalid guest note offset' USING ERRCODE='22023';
  END IF;
  SELECT event.status,guest.status INTO v_event_status,v_guest_status
  FROM eogp.event_participations guest JOIN eogp.events event
    ON event.organization_id=guest.organization_id AND event.id=guest.event_id
  WHERE guest.organization_id=p_org AND guest.event_id=p_event AND guest.id=p_guest;
  IF NOT FOUND THEN RAISE EXCEPTION 'participation not found' USING ERRCODE='P0002'; END IF;
  IF v_can_manage THEN
    BEGIN
      PERFORM eogp.assert_event_guest_notes_permission(p_org,p_event,p_actor,true);
    EXCEPTION WHEN insufficient_privilege THEN v_can_manage := false;
    END;
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'noteId',note.id,'createdAt',note.created_at,'withdrawnAt',note.withdrawn_at,
    'ciphertext',CASE WHEN note.withdrawn_at IS NULL THEN replace(encode(note.note_ciphertext,'base64'),E'\n','') END
  ) ORDER BY note.created_at DESC,note.id),'[]'::jsonb) INTO v_notes
  FROM (
    SELECT id,created_at,withdrawn_at,note_ciphertext FROM eogp.guest_notes
    WHERE organization_id=p_org AND event_id=p_event AND participation_id=p_guest AND storage_format='guest-note-v1'
    ORDER BY created_at DESC,id LIMIT 51 OFFSET p_offset
  ) note;
  INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,safe_metadata)
  VALUES(p_org,p_org,p_actor,'membership','guest.notes.viewed','event_participation',p_guest,jsonb_build_object('eventId',p_event));
  RETURN jsonb_build_object('notes',CASE WHEN jsonb_array_length(v_notes)>50 THEN v_notes-50 ELSE v_notes END,
    'nextOffset',CASE WHEN jsonb_array_length(v_notes)>50 AND p_offset<100000 THEN p_offset+50 END,
    'canManage',v_can_manage AND v_guest_status<>'cancelled' AND v_event_status IN ('draft','planned','scheduled','active'));
END;
$function$;

CREATE FUNCTION eogp.write_event_guest_note(p_org uuid,p_event uuid,p_actor uuid,p_guest uuid,p_note uuid,p_ciphertext bytea)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_guest_status text;
  v_note eogp.guest_notes%ROWTYPE;
  v_action text;
BEGIN
  PERFORM eogp.assert_event_guest_list_write(p_org,p_event,p_actor);
  PERFORM eogp.assert_event_guest_notes_permission(p_org,p_event,p_actor,true);
  SELECT status INTO v_guest_status FROM eogp.event_participations
  WHERE organization_id=p_org AND event_id=p_event AND id=p_guest FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'participation not found' USING ERRCODE='P0002'; END IF;
  IF v_guest_status='cancelled' THEN RAISE EXCEPTION 'cancelled participation cannot be edited' USING ERRCODE='55000'; END IF;

  IF p_ciphertext IS NOT NULL THEN
    INSERT INTO eogp.guest_notes(id,organization_id,event_id,participation_id,note_ciphertext,sensitivity,storage_format,created_by_membership_id)
    VALUES(p_note,p_org,p_event,p_guest,p_ciphertext,'restricted','guest-note-v1',p_actor) RETURNING * INTO v_note;
    v_action := 'guest.note.recorded';
  ELSE
    SELECT * INTO v_note FROM eogp.guest_notes
    WHERE organization_id=p_org AND event_id=p_event AND participation_id=p_guest AND id=p_note AND storage_format='guest-note-v1'
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'guest note not found' USING ERRCODE='P0002'; END IF;
    IF v_note.withdrawn_at IS NOT NULL THEN
      RETURN jsonb_build_object('noteId',v_note.id,'createdAt',v_note.created_at,'withdrawnAt',v_note.withdrawn_at);
    END IF;
    UPDATE eogp.guest_notes SET withdrawn_at=clock_timestamp(),withdrawn_by_membership_id=p_actor
    WHERE organization_id=p_org AND event_id=p_event AND participation_id=p_guest AND id=p_note RETURNING * INTO v_note;
    v_action := 'guest.note.withdrawn';
  END IF;
  INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,safe_metadata)
  VALUES(p_org,p_org,p_actor,'membership',v_action,'event_guest_note',v_note.id,
    jsonb_build_object('eventId',p_event,'participationId',p_guest));
  RETURN jsonb_build_object('noteId',v_note.id,'createdAt',v_note.created_at,'withdrawnAt',v_note.withdrawn_at);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.assert_event_guest_notes_permission(uuid,uuid,uuid,boolean),
  eogp.can_view_event_guest_notes(uuid,uuid,uuid),
  eogp.read_event_guest_notes(uuid,uuid,uuid,uuid,integer),
  eogp.write_event_guest_note(uuid,uuid,uuid,uuid,uuid,bytea) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.assert_event_guest_notes_permission(uuid,uuid,uuid,boolean),
  eogp.can_view_event_guest_notes(uuid,uuid,uuid),
  eogp.read_event_guest_notes(uuid,uuid,uuid,uuid,integer),
  eogp.write_event_guest_note(uuid,uuid,uuid,uuid,uuid,bytea) TO eventor_runtime;
