-- Revalidate the latest schedule and currently published RSVP policy at the SMTP authorization point.
CREATE FUNCTION eogp.authorize_invitation_email_submission(
  p_organization_id uuid,p_delivery_id uuid
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_delivery eogp.invitation_deliveries%ROWTYPE;
  v_invitation eogp.invitations%ROWTYPE;
  v_link eogp.invitation_links%ROWTYPE;
BEGIN
  IF session_user<>'eventor_worker'
     OR eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'invitation email authorization requires worker role and matching tenant context'
      USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_delivery FROM eogp.invitation_deliveries
   WHERE organization_id=p_organization_id AND id=p_delivery_id;
  IF NOT FOUND OR v_delivery.status<>'sending'
     OR v_delivery.lease_expires_at<=clock_timestamp() THEN
    RETURN false;
  END IF;

  SELECT * INTO v_invitation FROM eogp.invitations
   WHERE organization_id=p_organization_id AND id=v_delivery.invitation_id
   FOR SHARE;
  IF NOT FOUND OR v_invitation.status<>'active'
     OR v_invitation.current_revision_number<>(
       SELECT revision.revision_number FROM eogp.invitation_revisions revision
        WHERE revision.organization_id=p_organization_id
          AND revision.id=v_delivery.invitation_revision_id
          AND revision.invitation_id=v_invitation.id
     ) THEN
    RETURN false;
  END IF;

  SELECT * INTO v_link FROM eogp.invitation_links
   WHERE organization_id=p_organization_id
     AND invitation_id=v_delivery.invitation_id
     AND invitation_revision_id=v_delivery.invitation_revision_id
   FOR SHARE;
  IF NOT FOUND OR v_link.revoked_at IS NOT NULL
     OR v_link.expires_at<=clock_timestamp() THEN
    RETURN false;
  END IF;

  -- Recheck the delivery after obtaining the capability locks. A revocation
  -- that committed first is visible here; otherwise this authorization wins.
  PERFORM 1 FROM eogp.invitation_deliveries
   WHERE organization_id=p_organization_id AND id=p_delivery_id
     AND status='sending' AND lease_expires_at>clock_timestamp()
   FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;

  RETURN EXISTS (
    SELECT 1
      FROM eogp.events event
      JOIN eogp.event_schedule_revisions schedule
        ON schedule.organization_id=event.organization_id
       AND schedule.event_id=event.id
      JOIN eogp.invitation_revisions revision
        ON revision.organization_id=event.organization_id
       AND revision.event_id=event.id
       AND revision.id=v_delivery.invitation_revision_id
       AND revision.invitation_id=v_invitation.id
      JOIN eogp.rsvp_policy_revisions policy
        ON policy.organization_id=revision.organization_id
       AND policy.event_id=revision.event_id
       AND policy.id=revision.rsvp_policy_revision_id
      JOIN eogp.event_participations participation
        ON participation.organization_id=event.organization_id
       AND participation.event_id=event.id
      JOIN eogp.person_contact_points contact
        ON contact.organization_id=participation.organization_id
       AND contact.person_id=participation.person_id
     WHERE event.organization_id=p_organization_id
       AND event.id=v_delivery.event_id
       AND event.status NOT IN ('completed','cancelled','archived')
       AND schedule.id=revision.schedule_revision_id
       AND schedule.id=(
         SELECT latest.id
           FROM eogp.event_schedule_revisions latest
          WHERE latest.organization_id=p_organization_id
            AND latest.event_id=event.id
          ORDER BY latest.revision_number DESC
          LIMIT 1
       )
       AND policy.state='published'
       AND participation.id=v_invitation.participation_id
       AND participation.status='eligible'
       AND contact.contact_kind='email'
       AND contact.normalized_value_hash=v_delivery.destination_hash
       AND contact.is_primary AND contact.is_verified
       AND contact.contact_consent='permitted'
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.authorize_invitation_email_submission(uuid,uuid)
  FROM PUBLIC,eventor_runtime,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.authorize_invitation_email_submission(uuid,uuid)
  TO eventor_worker;
