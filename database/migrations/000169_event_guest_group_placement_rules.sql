CREATE TABLE eogp.guest_group_placement_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id uuid NOT NULL,
  first_group_id uuid NOT NULL,
  second_group_id uuid NOT NULL,
  placement_scope text NOT NULL CHECK (placement_scope IN ('table','zone','room')),
  condition text NOT NULL CHECK (condition IN ('together','apart')),
  priority text NOT NULL CHECK (priority IN ('required','preferred')),
  created_by_membership_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  retired_at timestamptz,
  retired_by_membership_id uuid,
  FOREIGN KEY (organization_id,event_id,first_group_id) REFERENCES eogp.guest_groups(organization_id,event_id,id),
  FOREIGN KEY (organization_id,event_id,second_group_id) REFERENCES eogp.guest_groups(organization_id,event_id,id),
  FOREIGN KEY (organization_id,created_by_membership_id) REFERENCES eogp.organization_memberships(organization_id,id),
  FOREIGN KEY (organization_id,retired_by_membership_id) REFERENCES eogp.organization_memberships(organization_id,id),
  CHECK (first_group_id < second_group_id),
  CHECK ((retired_at IS NULL) = (retired_by_membership_id IS NULL))
);
CREATE UNIQUE INDEX guest_group_placement_active_pair ON eogp.guest_group_placement_rules
  (organization_id,event_id,first_group_id,second_group_id,placement_scope) WHERE retired_at IS NULL;
CREATE INDEX guest_group_placement_event_idx ON eogp.guest_group_placement_rules(organization_id,event_id,retired_at);

ALTER TABLE eogp.guest_group_placement_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.guest_group_placement_rules FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON eogp.guest_group_placement_rules
  USING (organization_id = eogp.current_organization_id()) WITH CHECK (organization_id = eogp.current_organization_id());
REVOKE ALL ON eogp.guest_group_placement_rules FROM PUBLIC, eventor_runtime;

CREATE FUNCTION eogp.read_guest_group_placement_rules(p_org uuid,p_event uuid,p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_can_manage boolean;
  v_status text;
  v_rules jsonb;
BEGIN
  v_can_manage := eogp.assert_event_guest_list_access(p_org,p_event,p_actor);
  SELECT status INTO v_status FROM eogp.events WHERE organization_id=p_org AND id=p_event;
  IF NOT FOUND THEN RAISE EXCEPTION 'event not found' USING ERRCODE='P0002'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'ruleId',rule.id,'firstGroupId',rule.first_group_id,'secondGroupId',rule.second_group_id,
    'scope',rule.placement_scope,'condition',rule.condition,'priority',rule.priority,'retiredAt',rule.retired_at,
    'applicable',rule.retired_at IS NULL AND first_group.retired_at IS NULL AND second_group.retired_at IS NULL
  ) ORDER BY rule.retired_at IS NOT NULL,rule.created_at DESC,rule.id),'[]'::jsonb)
  INTO v_rules FROM eogp.guest_group_placement_rules rule
  JOIN eogp.guest_groups first_group ON (first_group.organization_id,first_group.event_id,first_group.id) =
    (rule.organization_id,rule.event_id,rule.first_group_id)
  JOIN eogp.guest_groups second_group ON (second_group.organization_id,second_group.event_id,second_group.id) =
    (rule.organization_id,rule.event_id,rule.second_group_id)
  WHERE rule.organization_id=p_org AND rule.event_id=p_event;
  RETURN jsonb_build_object('rules',v_rules,
    'canManage',v_can_manage AND v_status IN ('draft','planned','scheduled','active'));
END;
$function$;

CREATE FUNCTION eogp.write_guest_group_placement_rule(
  p_org uuid,p_event uuid,p_actor uuid,p_rule uuid,p_first uuid,p_second uuid,p_scope text,p_condition text,p_priority text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_rule eogp.guest_group_placement_rules%ROWTYPE;
  v_action text;
BEGIN
  PERFORM eogp.assert_event_guest_list_write(p_org,p_event,p_actor);
  IF p_rule IS NULL THEN
    IF p_first IS NULL OR p_second IS NULL OR p_first=p_second
      OR p_scope IS NULL OR p_scope NOT IN ('table','zone','room')
      OR p_condition IS NULL OR p_condition NOT IN ('together','apart')
      OR p_priority IS NULL OR p_priority NOT IN ('required','preferred') THEN
      RAISE EXCEPTION 'invalid group placement rule' USING ERRCODE='22023';
    END IF;
    IF (SELECT count(*) FROM eogp.guest_groups
      WHERE organization_id=p_org AND event_id=p_event AND id IN (p_first,p_second) AND retired_at IS NULL) <> 2 THEN
      RAISE EXCEPTION 'one or both groups are unavailable in this event' USING ERRCODE='P0002';
    END IF;
    INSERT INTO eogp.guest_group_placement_rules(organization_id,event_id,first_group_id,second_group_id,
      placement_scope,condition,priority,created_by_membership_id)
    VALUES(p_org,p_event,least(p_first,p_second),greatest(p_first,p_second),p_scope,p_condition,p_priority,p_actor)
    RETURNING * INTO v_rule;
    v_action := 'guest.group.placement_rule_created';
  ELSE
    SELECT * INTO v_rule FROM eogp.guest_group_placement_rules
    WHERE organization_id=p_org AND event_id=p_event AND id=p_rule FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'group placement rule not found' USING ERRCODE='P0002'; END IF;
    IF v_rule.retired_at IS NOT NULL THEN
      RETURN jsonb_build_object('ruleId',v_rule.id,'retiredAt',v_rule.retired_at);
    END IF;
    UPDATE eogp.guest_group_placement_rules SET retired_at=clock_timestamp(),retired_by_membership_id=p_actor
    WHERE organization_id=p_org AND event_id=p_event AND id=p_rule RETURNING * INTO v_rule;
    v_action := 'guest.group.placement_rule_retired';
  END IF;
  INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,safe_metadata)
  VALUES(p_org,p_org,p_actor,'membership',v_action,'guest_group_placement_rule',v_rule.id,
    jsonb_build_object('eventId',p_event,'firstGroupId',v_rule.first_group_id,'secondGroupId',v_rule.second_group_id,
      'scope',v_rule.placement_scope,'priority',v_rule.priority,'condition',v_rule.condition));
  RETURN jsonb_build_object('ruleId',v_rule.id,'retiredAt',v_rule.retired_at);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.read_guest_group_placement_rules(uuid,uuid,uuid),
  eogp.write_guest_group_placement_rule(uuid,uuid,uuid,uuid,uuid,uuid,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.read_guest_group_placement_rules(uuid,uuid,uuid),
  eogp.write_guest_group_placement_rule(uuid,uuid,uuid,uuid,uuid,uuid,text,text,text) TO eventor_runtime;
