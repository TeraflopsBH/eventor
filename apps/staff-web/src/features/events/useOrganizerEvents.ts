import { computed, ref, type Ref } from "vue";
import type {
  CreateOrganizerEventInput,
  CreateOrganizerEventSessionInput,
  OrganizerEvent,
  OrganizerEventAction,
  OrganizerEventSessionAction,
  OrganizerEventSessionDetails,
  UpdateOrganizerEventDetailsInput,
  UpdateOrganizerEventSessionInput,
} from "../../api";

interface Dependencies {
  api: typeof import("../../api").api;
  organizationId: Ref<string>;
  busy: Ref<boolean>;
  pageError: Ref<string>;
  pageNotice: Ref<string>;
  clearMessages: () => void;
  showError: (error: unknown) => void;
  translate: (key: string, params?: Record<string, string | number>) => string;
}

export function useOrganizerEvents({
  api, organizationId, busy, pageError, pageNotice, clearMessages, showError, translate,
}: Dependencies) {
  const events = ref<OrganizerEvent[]>([]);
  const selectedEventId = ref("");
  const selectedEvent = computed(() => events.value.find((event) => event.eventId === selectedEventId.value) ?? null);
  const sessions = ref<OrganizerEventSessionDetails[] | null>(null);
  const sessionsEventId = ref("");
  const canArchive = (event: OrganizerEvent) => !["active", "scheduled", "archived"].includes(event.status);

  async function loadEvents(): Promise<void> {
    if (!organizationId.value) {
      events.value = [];
      selectedEventId.value = "";
      return;
    }
    const result = await api.getOrganizerEvents(organizationId.value);
    events.value = result.data;
    if (!events.value.some((event) => event.eventId === sessionsEventId.value)) {
      closeSessions();
    }
    if (!events.value.some((event) => event.eventId === selectedEventId.value)) {
      selectedEventId.value = events.value[0]?.eventId ?? "";
    }
  }

  async function refresh(): Promise<void> {
    clearMessages();
    busy.value = true;
    try {
      await loadEvents();
      if (sessionsEventId.value) await loadSessions(sessionsEventId.value);
    } catch (error) {
      showError(error);
    } finally {
      busy.value = false;
    }
  }

  async function open(): Promise<void> {
    selectedEventId.value = "";
    await refresh();
  }

  function reset(): void {
    events.value = [];
    selectedEventId.value = "";
    closeSessions();
  }

  async function createEvent(input: CreateOrganizerEventInput): Promise<boolean> {
    clearMessages();
    busy.value = true;
    try {
      const result = await api.createOrganizerEvent(organizationId.value, input);
      selectedEventId.value = result.data.eventId;
      pageNotice.value = translate("events.created");
      try { await loadEvents(); } catch (error) { showError(error); }
      return true;
    } catch (error) {
      showError(error);
      return false;
    } finally {
      busy.value = false;
    }
  }

  async function updateEvent(event: OrganizerEvent, input: Omit<UpdateOrganizerEventDetailsInput, "expectedDetailsRevision">): Promise<boolean> {
    clearMessages();
    busy.value = true;
    try {
      await api.updateOrganizerEventDetails(organizationId.value, event.eventId, {
        ...input,
        expectedDetailsRevision: event.detailsRevision,
      });
      pageNotice.value = translate("events.updated");
      try { await loadEvents(); } catch (error) { showError(error); }
      return true;
    } catch (error) {
      showError(error);
      return false;
    } finally {
      busy.value = false;
    }
  }

  async function transitionEvent(event: OrganizerEvent, action: OrganizerEventAction): Promise<boolean> {
    const confirmation = action === "publish" ? "events.confirmPublish" : action === "complete" ? "events.confirmClose" : null;
    if (confirmation && !window.confirm(translate(confirmation, { title: event.title }))) {
      return false;
    }
    clearMessages();
    busy.value = true;
    try {
      await api.transitionOrganizerEvent(organizationId.value, event.eventId, {
        action,
        expectedDetailsRevision: event.detailsRevision,
        expectedScheduleRevision: event.currentRevision,
      });
      pageNotice.value = translate("events.lifecycleUpdated");
      try { await loadEvents(); } catch (error) { showError(error); }
      return true;
    } catch (error) {
      showError(error);
      return false;
    } finally {
      busy.value = false;
    }
  }

  async function enableGuestRegistry(event: OrganizerEvent): Promise<void> {
    clearMessages();
    busy.value = true;
    try {
      await api.enableEventGuestRegistry(event.eventId);
      pageNotice.value = translate("events.guestListEnabled");
      await loadEvents();
    } catch (error) {
      showError(error);
    } finally {
      busy.value = false;
    }
  }

  async function archiveEvent(event: OrganizerEvent): Promise<void> {
    if (!canArchive(event)) {
      pageError.value = translate("events.archiveUnavailable");
      return;
    }
    if (!window.confirm(translate("events.confirmArchive", { title: event.title }))) return;
    clearMessages();
    busy.value = true;
    try {
      await api.archiveOrganizerEvent(organizationId.value, event.eventId, event.detailsRevision);
      pageNotice.value = translate("events.archived");
      await loadEvents();
    } catch (error) {
      showError(error);
    } finally {
      busy.value = false;
    }
  }

  function closeSessions(): void {
    sessionsEventId.value = "";
    sessions.value = null;
  }

  async function loadSessions(eventId: string): Promise<void> {
    const result = await api.getOrganizerEventSessions(organizationId.value, eventId);
    if (sessionsEventId.value === eventId) sessions.value = result.data;
  }

  async function showSessions(eventId: string): Promise<void> {
    if (eventId === sessionsEventId.value) {
      closeSessions();
      return;
    }
    clearMessages();
    busy.value = true;
    sessionsEventId.value = eventId;
    sessions.value = null;
    try {
      await loadSessions(eventId);
    } catch (error) {
      showError(error);
    } finally {
      busy.value = false;
    }
  }

  async function createSession(eventId: string, input: CreateOrganizerEventSessionInput): Promise<boolean> {
    clearMessages();
    busy.value = true;
    try {
      await api.createOrganizerEventSession(organizationId.value, eventId, input);
      pageNotice.value = translate("events.sessionCreated");
      try { await loadSessions(eventId); } catch (error) { showError(error); }
      return true;
    } catch (error) {
      showError(error);
      return false;
    } finally {
      busy.value = false;
    }
  }

  async function updateSession(
    eventId: string,
    sessionId: string,
    input: UpdateOrganizerEventSessionInput,
  ): Promise<boolean> {
    clearMessages();
    busy.value = true;
    try {
      await api.updateOrganizerEventSession(organizationId.value, eventId, sessionId, input);
      pageNotice.value = translate("events.sessionUpdated");
      try { await loadSessions(eventId); } catch (error) { showError(error); }
      return true;
    } catch (error) {
      showError(error);
      return false;
    } finally {
      busy.value = false;
    }
  }

  async function transitionSession(
    event: OrganizerEvent,
    session: OrganizerEventSessionDetails,
    action: OrganizerEventSessionAction,
  ): Promise<void> {
    clearMessages();
    busy.value = true;
    try {
      await api.transitionOrganizerEventSession(organizationId.value, event.eventId, session.sessionId, {
        action,
        expectedDetailsRevision: session.detailsRevision,
        expectedScheduleRevision: event.currentRevision,
      });
      pageNotice.value = translate("events.sessionUpdated");
      await loadSessions(event.eventId);
    } catch (error) {
      showError(error);
    } finally {
      busy.value = false;
    }
  }

  return {
    events,
    sessions,
    sessionsEventId,
    showSessions,
    createSession,
    updateSession,
    transitionSession,
    selectedEventId,
    selectedEvent,
    canArchive,
    loadEvents,
    refresh,
    open,
    reset,
    createEvent,
    updateEvent,
    archiveEvent,
    enableGuestRegistry,
    transitionEvent,
  };
}
