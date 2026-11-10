-- Authentication sessions and event-change notification preparation worker.
-- No raw bearer or CSRF secret is persisted. The worker prepares a reviewable
-- campaign snapshot; it does not send email/SMS or mark any delivery as sent.

ALTER TABLE eogp.organization_memberships
  ADD CONSTRAINT organization_memberships_session_identity_uq
  UNIQUE (organization_id, id, user_id);

CREATE TABLE eogp.user_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  organization_id uuid NOT NULL,
  membership_id uuid NOT NULL,
  session_token_sha256 text NOT NULL UNIQUE
    CHECK (session_token_sha256 ~ '^[0-9a-f]{64}$'),
  csrf_token_sha256 text NOT NULL
    CHECK (csrf_token_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at timestamptz NOT NULL,
  last_seen_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  revoked_at timestamptz,
  source_fingerprint text
    CHECK (source_fingerprint IS NULL OR source_fingerprint ~ '^[0-9a-f]{64}$'),
  user_agent_fingerprint text
    CHECK (user_agent_fingerprint IS NULL OR user_agent_fingerprint ~ '^[0-9a-f]{64}$'),
  FOREIGN KEY (user_id) REFERENCES eogp.users(id),
  FOREIGN KEY (organization_id, membership_id, user_id)
    REFERENCES eogp.organization_memberships(organization_id, id, user_id),
  CHECK (expires_at > created_at),
  CHECK (revoked_at IS NULL OR revoked_at >= created_at)
);
CREATE INDEX user_sessions_active_user_idx
  ON eogp.user_sessions (user_id, expires_at DESC)
  WHERE revoked_at IS NULL;
CREATE INDEX user_sessions_active_membership_idx
  ON eogp.user_sessions (organization_id, membership_id, expires_at DESC)
  WHERE revoked_at IS NULL;

ALTER TABLE eogp.user_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.user_sessions FORCE ROW LEVEL SECURITY;
CREATE POLICY user_sessions_tenant_isolation ON eogp.user_sessions
  USING (organization_id = eogp.current_organization_id())
  WITH CHECK (organization_id = eogp.current_organization_id());
CREATE POLICY user_sessions_auth_service_access ON eogp.user_sessions
  FOR ALL TO eventor_auth
  USING (true)
  WITH CHECK (true);

CREATE TABLE eogp.auth_login_attempts (
  email_fingerprint text NOT NULL CHECK (email_fingerprint ~ '^[0-9a-f]{64}$'),
  source_fingerprint text NOT NULL CHECK (source_fingerprint ~ '^[0-9a-f]{64}$'),
  window_started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  failed_attempts integer NOT NULL DEFAULT 0 CHECK (failed_attempts >= 0),
  blocked_until timestamptz,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (email_fingerprint, source_fingerprint)
);
ALTER TABLE eogp.auth_login_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.auth_login_attempts FORCE ROW LEVEL SECURITY;
CREATE POLICY auth_login_attempts_auth_service_access ON eogp.auth_login_attempts
  FOR ALL TO eventor_auth
  USING (true)
  WITH CHECK (true);

REVOKE ALL ON eogp.user_sessions, eogp.auth_login_attempts
  FROM PUBLIC, eventor_runtime, eventor_worker;
GRANT SELECT, INSERT, UPDATE ON eogp.user_sessions, eogp.auth_login_attempts
  TO eventor_auth;

-- A worker may discover only the tenant IDs of pending organizer event-change
-- messages. It still has to set that tenant's transaction-local context before
-- reading or changing any event, recipient, template or campaign rows.
ALTER TABLE eogp.outbox_events
  ADD COLUMN dead_lettered_at timestamptz;
DROP INDEX eogp.outbox_ready_idx;
CREATE INDEX outbox_ready_idx
  ON eogp.outbox_events (available_at, occurred_at)
  WHERE published_at IS NULL AND dead_lettered_at IS NULL;
CREATE POLICY worker_event_notification_outbox_discovery
  ON eogp.outbox_events
  FOR SELECT TO eventor_worker
  USING (
    topic = 'event.change.notification_requested'
    AND published_at IS NULL
    AND dead_lettered_at IS NULL
  );

GRANT SELECT ON
  eogp.events,
  eogp.event_schedule_revisions,
  eogp.event_change_requests,
  eogp.event_decisions,
  eogp.event_participations,
  eogp.persons,
  eogp.person_contact_points,
  eogp.invitations,
  eogp.rsvp_responses,
  eogp.notification_templates
TO eventor_worker;

GRANT SELECT, INSERT, UPDATE ON eogp.event_notification_campaigns TO eventor_worker;
GRANT SELECT, INSERT ON
  eogp.event_notification_recipients,
  eogp.event_notification_exclusions
TO eventor_worker;

DO $preflight$
BEGIN
  IF EXISTS (
    SELECT 1
      FROM eogp.event_notification_campaigns
     GROUP BY organization_id, event_decision_id, purpose
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION
      '000031 requires review of duplicate notification campaigns for an event decision and purpose'
      USING ERRCODE = '23505',
            HINT = 'Resolve duplicate campaign ownership and recipient snapshots before retrying the migration.';
  END IF;
END;
$preflight$;

CREATE UNIQUE INDEX event_notification_campaign_decision_purpose_uq
  ON eogp.event_notification_campaigns (organization_id, event_decision_id, purpose);

CREATE FUNCTION eogp.process_event_notification_outbox(
  p_batch_size integer DEFAULT 20
) RETURNS jsonb
LANGUAGE plpgsql
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_item record;
  v_decision record;
  v_template_revision_id uuid;
  v_campaign_id uuid;
  v_custom_ids uuid[];
  v_audience text;
  v_purpose text;
  v_attempt integer;
  v_sqlstate text;
  v_prepared integer := 0;
  v_deferred integer := 0;
  v_dead_lettered integer := 0;
  v_processed integer := 0;
  v_inserted_count integer;
BEGIN
  IF current_user <> 'eventor_worker' THEN
    RAISE EXCEPTION 'notification outbox processing requires eventor_worker'
      USING ERRCODE = '42501';
  END IF;
  IF eogp.current_organization_id() IS NULL THEN
    RAISE EXCEPTION 'tenant context is required for notification outbox processing'
      USING ERRCODE = '42501';
  END IF;
  IF p_batch_size IS NULL OR p_batch_size < 1 OR p_batch_size > 100 THEN
    RAISE EXCEPTION 'notification outbox batch size must be between 1 and 100'
      USING ERRCODE = '22023';
  END IF;

  FOR v_item IN
    SELECT outbox.*
      FROM eogp.outbox_events AS outbox
     WHERE outbox.organization_id = eogp.current_organization_id()
       AND outbox.topic = 'event.change.notification_requested'
       AND outbox.published_at IS NULL
       AND outbox.dead_lettered_at IS NULL
       AND outbox.available_at <= clock_timestamp()
     ORDER BY outbox.available_at, outbox.occurred_at, outbox.id
     FOR UPDATE SKIP LOCKED
     LIMIT p_batch_size
  LOOP
    v_processed := v_processed + 1;
    v_attempt := v_item.attempt_count + 1;
    v_campaign_id := NULL;
    v_inserted_count := 0;

    BEGIN
      IF jsonb_typeof(v_item.payload) IS DISTINCT FROM 'object'
         OR nullif(v_item.payload ->> 'eventDecisionId','') IS NULL
         OR nullif(v_item.payload ->> 'decisionKind','') IS NULL
         OR nullif(v_item.payload ->> 'audienceKind','') IS NULL THEN
        RAISE EXCEPTION 'invalid event notification outbox payload'
          USING ERRCODE = '22023';
      END IF;

      BEGIN
        v_custom_ids := ARRAY(
          SELECT value::uuid
            FROM jsonb_array_elements_text(
              coalesce(v_item.payload -> 'customParticipationIds','[]'::jsonb)
            ) AS item(value)
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'invalid custom audience identifier payload'
          USING ERRCODE = '22023';
      END;

      v_audience := v_item.payload ->> 'audienceKind';
      IF v_audience NOT IN (
        'accepted_tentative','all_active_invitees','all_previously_invited','custom'
      ) THEN
        RAISE EXCEPTION 'unsupported event notification audience'
          USING ERRCODE = '22023';
      END IF;
      IF (v_audience = 'custom' AND cardinality(v_custom_ids) = 0)
         OR (v_audience <> 'custom' AND cardinality(v_custom_ids) > 0) THEN
        RAISE EXCEPTION 'custom audience identifiers do not match audience kind'
          USING ERRCODE = '22023';
      END IF;

      SELECT
        decision.id,
        decision.event_id,
        decision.decision_kind,
        decision.replacement_schedule_revision_id,
        decision.executed_by_organization_id,
        decision.executed_by_membership_id,
        schedule.reconfirmation_policy
        INTO v_decision
        FROM eogp.event_decisions AS decision
        LEFT JOIN eogp.event_schedule_revisions AS schedule
          ON schedule.organization_id = decision.organization_id
         AND schedule.event_id = decision.event_id
         AND schedule.id = decision.replacement_schedule_revision_id
       WHERE decision.organization_id = v_item.organization_id
         AND decision.id = (v_item.payload ->> 'eventDecisionId')::uuid
         AND decision.event_id = v_item.aggregate_id;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'event decision referenced by notification outbox was not found'
          USING ERRCODE = 'P0002';
      END IF;
      IF v_decision.decision_kind <> v_item.payload ->> 'decisionKind' THEN
        RAISE EXCEPTION 'event notification decision kind does not match its decision row'
          USING ERRCODE = '23514';
      END IF;

      v_purpose := CASE v_decision.decision_kind
        WHEN 'cancelled' THEN 'event_cancellation'
        WHEN 'postponed' THEN 'event_postponement'
        WHEN 'rescheduled' THEN
          CASE
            WHEN coalesce(v_decision.reconfirmation_policy,'none') = 'none'
              THEN 'schedule_update'
            ELSE 'rsvp_reconfirmation'
          END
      END;
      IF v_purpose IS NULL THEN
        RAISE EXCEPTION 'unsupported event decision notification purpose'
          USING ERRCODE = '22023';
      END IF;

      SELECT revision.id
        INTO v_template_revision_id
        FROM eogp.notification_template_revisions AS revision
        JOIN eogp.notification_templates AS template
          ON template.organization_id = revision.organization_id
         AND template.id = revision.template_id
       WHERE revision.organization_id = v_item.organization_id
         AND template.purpose = v_purpose
         AND template.status = 'active'
         AND revision.state = 'published'
       ORDER BY (revision.locale = 'bs-BA') DESC,
                revision.revision_number DESC,
                revision.created_at DESC
       LIMIT 1;

      IF v_template_revision_id IS NULL THEN
        RAISE EXCEPTION 'no published notification template is configured for this purpose'
          USING ERRCODE = '55000';
      END IF;

      INSERT INTO eogp.event_notification_campaigns (
        organization_id, event_id, event_decision_id, purpose, audience_kind,
        status, template_revision_id, audience_rules_snapshot,
        created_by_organization_id, created_by_membership_id
      ) VALUES (
        v_item.organization_id,
        v_decision.event_id,
        v_decision.id,
        v_purpose,
        v_audience,
        'previewed',
        v_template_revision_id,
        jsonb_build_object(
          'source', 'event.change.notification_requested',
          'outboxEventId', v_item.id,
          'eventDecisionId', v_decision.id,
          'decisionKind', v_decision.decision_kind,
          'audienceKind', v_audience,
          'customParticipationIds', to_jsonb(v_custom_ids),
          'replacementScheduleRevisionId', v_decision.replacement_schedule_revision_id,
          'contactEligibility', 'verified_and_permitted_email_or_phone',
          'snapshotSemantics', 'previewed_pending_operator_confirmation',
          'preparedAt', clock_timestamp()
        ),
        v_decision.executed_by_organization_id,
        v_decision.executed_by_membership_id
      )
      ON CONFLICT (organization_id, event_decision_id, purpose) DO NOTHING
      RETURNING id INTO v_campaign_id;

      IF v_campaign_id IS NOT NULL THEN
        WITH latest_rsvp AS (
          SELECT DISTINCT ON (response.participation_id)
            response.participation_id,
            response.response
          FROM eogp.rsvp_responses AS response
          WHERE response.organization_id = v_item.organization_id
            AND response.event_id = v_decision.event_id
          ORDER BY response.participation_id,
                   response.sequence_number DESC,
                   response.received_at DESC,
                   response.id DESC
        ),
        latest_invitation AS (
          SELECT DISTINCT ON (invitation.participation_id)
            invitation.participation_id,
            invitation.id AS invitation_id,
            invitation.status
          FROM eogp.invitations AS invitation
          WHERE invitation.organization_id = v_item.organization_id
            AND invitation.event_id = v_decision.event_id
          ORDER BY invitation.participation_id,
                   invitation.created_at DESC,
                   invitation.id DESC
        ),
        latest_previously_issued_invitation AS (
          SELECT DISTINCT ON (invitation.participation_id)
            invitation.participation_id,
            invitation.id AS invitation_id
          FROM eogp.invitations AS invitation
          WHERE invitation.organization_id = v_item.organization_id
            AND invitation.event_id = v_decision.event_id
            AND invitation.issued_at IS NOT NULL
          ORDER BY invitation.participation_id,
                   invitation.issued_at DESC,
                   invitation.created_at DESC,
                   invitation.id DESC
        ),
        candidates AS (
          SELECT
            participation.id AS participation_id,
            participation.person_id,
            CASE
              WHEN v_audience = 'all_previously_invited'
                THEN coalesce(previous_invitation.invitation_id, invitation.invitation_id)
              ELSE invitation.invitation_id
            END AS invitation_id,
            CASE v_audience
              WHEN 'accepted_tentative' THEN 'latest_rsvp_accepted_or_tentative'
              WHEN 'all_active_invitees' THEN 'active_invitation'
              WHEN 'all_previously_invited' THEN 'previously_invited'
              ELSE 'custom_selection'
            END AS qualification_reason
          FROM eogp.event_participations AS participation
          LEFT JOIN latest_rsvp AS response
            ON response.participation_id = participation.id
          LEFT JOIN latest_invitation AS invitation
            ON invitation.participation_id = participation.id
          LEFT JOIN latest_previously_issued_invitation AS previous_invitation
            ON previous_invitation.participation_id = participation.id
          WHERE participation.organization_id = v_item.organization_id
            AND participation.event_id = v_decision.event_id
            AND participation.status IN ('eligible','waitlisted')
            AND (
              (v_audience = 'accepted_tentative'
                AND response.response IN ('accepted','tentative'))
              OR
              (v_audience = 'all_active_invitees'
                AND invitation.status = 'active')
              OR
              (v_audience = 'all_previously_invited'
                AND previous_invitation.invitation_id IS NOT NULL)
              OR
              (v_audience = 'custom'
                AND participation.id = ANY(v_custom_ids))
            )
        ),
        contact_choices AS (
          SELECT DISTINCT ON (candidate.participation_id, contact.contact_kind)
            candidate.participation_id,
            candidate.invitation_id,
            candidate.qualification_reason,
            contact.contact_kind,
            contact.encrypted_value,
            contact.normalized_value_hash
          FROM candidates AS candidate
          JOIN eogp.person_contact_points AS contact
            ON contact.organization_id = v_item.organization_id
           AND contact.person_id = candidate.person_id
          WHERE contact.contact_kind IN ('email','phone')
            AND contact.is_verified
            AND contact.contact_consent = 'permitted'
          ORDER BY candidate.participation_id,
                   contact.contact_kind,
                   contact.is_primary DESC,
                   contact.updated_at DESC,
                   contact.id
        )
        INSERT INTO eogp.event_notification_recipients (
          organization_id, event_id, campaign_id, participation_id,
          invitation_id, qualification_reason, channel,
          destination_ciphertext, destination_hash
        )
        SELECT
          v_item.organization_id,
          v_decision.event_id,
          v_campaign_id,
          choice.participation_id,
          choice.invitation_id,
          choice.qualification_reason,
          CASE choice.contact_kind WHEN 'email' THEN 'email' ELSE 'sms' END,
          choice.encrypted_value,
          choice.normalized_value_hash
        FROM contact_choices AS choice;
        GET DIAGNOSTICS v_inserted_count = ROW_COUNT;

        WITH latest_invitation AS (
          SELECT DISTINCT ON (invitation.participation_id)
            invitation.participation_id,
            invitation.id AS invitation_id
          FROM eogp.invitations AS invitation
          WHERE invitation.organization_id = v_item.organization_id
            AND invitation.event_id = v_decision.event_id
          ORDER BY invitation.participation_id,
                   invitation.created_at DESC,
                   invitation.id DESC
        ),
        candidates AS (
          SELECT
            participation.id AS participation_id,
            invitation.invitation_id
          FROM eogp.event_participations AS participation
          LEFT JOIN latest_invitation AS invitation
            ON invitation.participation_id = participation.id
          LEFT JOIN LATERAL (
            SELECT response.response
              FROM eogp.rsvp_responses AS response
             WHERE response.organization_id = participation.organization_id
               AND response.event_id = participation.event_id
               AND response.participation_id = participation.id
             ORDER BY response.sequence_number DESC,
                      response.received_at DESC,
                      response.id DESC
             LIMIT 1
          ) AS latest_response ON true
          WHERE participation.organization_id = v_item.organization_id
            AND participation.event_id = v_decision.event_id
            AND participation.status IN ('eligible','waitlisted')
            AND (
              (v_audience = 'accepted_tentative'
                AND latest_response.response IN ('accepted','tentative'))
              OR
              (v_audience = 'all_active_invitees'
                AND invitation.invitation_id IS NOT NULL
                AND EXISTS (
                  SELECT 1 FROM eogp.invitations active_invitation
                   WHERE active_invitation.organization_id = participation.organization_id
                     AND active_invitation.event_id = participation.event_id
                     AND active_invitation.id = invitation.invitation_id
                     AND active_invitation.status = 'active'
                ))
              OR
              (v_audience = 'all_previously_invited'
                AND EXISTS (
                  SELECT 1 FROM eogp.invitations previous_invitation
                   WHERE previous_invitation.organization_id = participation.organization_id
                     AND previous_invitation.event_id = participation.event_id
                     AND previous_invitation.participation_id = participation.id
                     AND previous_invitation.issued_at IS NOT NULL
                ))
              OR
              (v_audience = 'custom' AND participation.id = ANY(v_custom_ids))
            )
            AND NOT EXISTS (
              SELECT 1
                FROM eogp.person_contact_points AS contact
               WHERE contact.organization_id = participation.organization_id
                 AND contact.person_id = participation.person_id
                 AND contact.contact_kind IN ('email','phone')
                 AND contact.is_verified
                 AND contact.contact_consent = 'permitted'
            )
        )
        INSERT INTO eogp.event_notification_exclusions (
          organization_id, event_id, campaign_id, participation_id,
          invitation_id, exclusion_reason,
          actor_organization_id, actor_membership_id
        )
        SELECT
          v_item.organization_id,
          v_decision.event_id,
          v_campaign_id,
          candidate.participation_id,
          candidate.invitation_id,
          'no_verified_permitted_contact',
          v_decision.executed_by_organization_id,
          v_decision.executed_by_membership_id
        FROM candidates AS candidate;

        UPDATE eogp.event_notification_campaigns
           SET recipient_count = v_inserted_count
         WHERE organization_id = v_item.organization_id
           AND id = v_campaign_id;
        v_prepared := v_prepared + 1;
      END IF;

      UPDATE eogp.outbox_events
         SET claimed_at = clock_timestamp(),
             published_at = clock_timestamp(),
             attempt_count = attempt_count + 1,
             last_error_code = NULL
       WHERE organization_id = v_item.organization_id
         AND id = v_item.id;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE;
      v_attempt := v_item.attempt_count + 1;
      IF v_attempt >= 12 THEN
        UPDATE eogp.outbox_events
           SET attempt_count = v_attempt,
               claimed_at = NULL,
               dead_lettered_at = clock_timestamp(),
               last_error_code = 'sqlstate_' || coalesce(v_sqlstate,'unknown')
         WHERE organization_id = v_item.organization_id
           AND id = v_item.id;
        v_dead_lettered := v_dead_lettered + 1;
      ELSE
        UPDATE eogp.outbox_events
           SET attempt_count = v_attempt,
               claimed_at = NULL,
               available_at = clock_timestamp()
                 + make_interval(secs => least(3600, (30 * power(2, least(v_attempt - 1, 7)))::integer)),
               last_error_code = 'sqlstate_' || coalesce(v_sqlstate,'unknown')
         WHERE organization_id = v_item.organization_id
           AND id = v_item.id;
        v_deferred := v_deferred + 1;
      END IF;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'processed', v_processed,
    'campaignPreviewsPrepared', v_prepared,
    'deferred', v_deferred,
    'deadLettered', v_dead_lettered
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.process_event_notification_outbox(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.process_event_notification_outbox(integer) TO eventor_worker;
