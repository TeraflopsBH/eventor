-- Match the existing SECURITY DEFINER trust boundary; public is not trusted.
ALTER FUNCTION eogp.create_organizer_event(uuid,uuid,text,text,text,timestamptz,timestamptz,text,jsonb,jsonb)
  SET search_path = pg_catalog, eogp;
ALTER FUNCTION eogp.list_organizer_events(uuid,uuid)
  SET search_path = pg_catalog, eogp;
ALTER FUNCTION eogp.update_organizer_event_details(uuid,uuid,uuid,integer,text,text)
  SET search_path = pg_catalog, eogp;
ALTER FUNCTION eogp.archive_organizer_event(uuid,uuid,uuid,integer)
  SET search_path = pg_catalog, eogp;
