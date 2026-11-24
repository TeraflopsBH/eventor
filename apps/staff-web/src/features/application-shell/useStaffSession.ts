import { acknowledgeStaffLocale, pendingStaffLocale, queueStaffLocale, rememberStaffLocale } from "../../i18n/staff-locale";
import { computed, reactive, ref, type Ref } from "vue";
import { ApiError, type Principal } from "../../api";
import { formatApiError } from "../../i18n/api-errors";

export type StaffTab = "delivery" | "campaign" | "inquiries" | "approvals" | "prices" | "cancellations"
  | "taxes" | "forms" | "guest-invitations" | "guest-registry" | "event-guests" | "events" | "settings";

interface StaffSessionDependencies {
  api: typeof import("../../api").api;
  busy: Ref<boolean>;
  pageError: Ref<string>;
  pageNotice: Ref<string>;
  clearMessages: () => void;
  resetWorkspace: () => void;
  translate: (key: string, params?: Record<string, string | number>) => string;
  applyLocale: (locale: string) => void;
  applyWorkspaces: (workspaces: StaffTab[]) => void;
}

export function useStaffSession({
  api, busy, pageError, pageNotice, clearMessages, resetWorkspace, translate, applyLocale, applyWorkspaces,
}: StaffSessionDependencies) {
  const principal = ref<Principal | null>(null);
  const loadingSession = ref(true);
  const workspaces = ref<StaffTab[]>([]);
  let preferenceWrites: Promise<void> = Promise.resolve();
  const loginForm = reactive({ email: "", password: "", organizationSlug: "" });
  const selectedOrganization = computed(() =>
    principal.value?.memberships?.find((membership) => membership.selected)?.organizationName
    ?? principal.value?.organizationId
    ?? "",
  );

  function showError(error: unknown): void {
    if (error instanceof ApiError) {
      if (error.code === "UNAUTHENTICATED") {
        principal.value = null;
        resetWorkspace();
        pageError.value = translate("auth.sessionExpired");
        return;
      }
      pageError.value = formatApiError(error, translate);
      return;
    }
    pageError.value = error instanceof Error ? error.message : translate("common.unexpectedError");
  }

  async function refreshSession(): Promise<void> {
    loadingSession.value = true;
    try {
      const result = await api.me();
      principal.value = result.data;
      const pending = pendingStaffLocale(result.data.userId);
      let preferred = result.data.userLocale ?? result.data.organizationDefaultLocale ?? "en";
      if (pending) {
        preferred = pending.locale;
        try {
          const saved = await api.updateUserLocale(pending.locale);
          principal.value.userLocale = saved.data.userLocale;
          acknowledgeStaffLocale(pending);
        } catch (error) { showError(error); }
      }
      applyLocale(preferred);
      rememberStaffLocale(preferred);
      const available = await api.getStaffWorkspaces();
      workspaces.value = available.data.workspaces;
      applyWorkspaces(workspaces.value);

    } catch (error) {
      if (error instanceof ApiError && error.status === 401) {
        principal.value = null;
      } else {
        showError(error);
      }
    } finally {
      loadingSession.value = false;
    }
  }

  async function signIn(): Promise<void> {
    clearMessages();
    busy.value = true;
    try {
      await api.login({
        email: loginForm.email.trim(),
        password: loginForm.password,
        organizationSlug: loginForm.organizationSlug.trim(),
      });
      loginForm.password = "";
      await refreshSession();
      if (principal.value) pageNotice.value = translate("auth.signedIn");
    } catch (error) {
      showError(error);
    } finally {
      busy.value = false;
    }
  }

  async function saveLocalePreference(locale: string): Promise<void> {
    if (locale !== "bs-BA" && locale !== "en") return;
    const userId = principal.value?.userId ?? null;
    const pending = queueStaffLocale(locale, userId);
    if (!userId) return;
    preferenceWrites = preferenceWrites.then(async () => {
      if (principal.value?.userId !== userId) return;
      try {
        const result = await api.updateUserLocale(locale);
        if (principal.value?.userId === userId) principal.value.userLocale = result.data.userLocale;
        acknowledgeStaffLocale(pending);
        pageNotice.value = translate("localeSettings.userSaved");
      } catch (error) { showError(error); }
    });
    await preferenceWrites;
  }

  async function useOrganizationLocalePreference(): Promise<void> {
    if (!principal.value) return;
    try {
      const organization = await api.getOrganizationLocale();
      await api.updateUserLocale(null);
      principal.value.userLocale = null;
      principal.value.organizationDefaultLocale = organization.data.defaultLocale;
      applyLocale(organization.data.defaultLocale);
      rememberStaffLocale(organization.data.defaultLocale);
      const pending = pendingStaffLocale(principal.value.userId);
      if (pending) acknowledgeStaffLocale(pending);
      pageNotice.value = translate("localeSettings.followOrganization");
    } catch (error) {
      showError(error);
    }
  }

  async function signOut(): Promise<void> {
    clearMessages();
    busy.value = true;
    try {
      await api.logout();
      principal.value = null;
      resetWorkspace();
      pageNotice.value = translate("auth.signedOut");
    } catch (error) {
      showError(error);
    } finally {
      busy.value = false;
    }
  }

  return { principal, loadingSession, workspaces, loginForm, selectedOrganization, showError, refreshSession, signIn, signOut, saveLocalePreference, useOrganizationLocalePreference };
}
