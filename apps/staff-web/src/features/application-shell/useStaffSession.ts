import { computed, reactive, ref, type Ref } from "vue";
import { ApiError, type Principal } from "../../api";
import { formatApiError } from "../../i18n/api-errors";

interface StaffSessionDependencies {
  api: typeof import("../../api").api;
  busy: Ref<boolean>;
  pageError: Ref<string>;
  pageNotice: Ref<string>;
  clearMessages: () => void;
  loadConfiguration: () => Promise<void>;
  resetWorkspace: () => void;
  translate: (key: string, params?: Record<string, string | number>) => string;
  applyLocale: (locale: string) => void;
}

export function useStaffSession({
  api, busy, pageError, pageNotice, clearMessages, loadConfiguration, resetWorkspace, translate, applyLocale,
}: StaffSessionDependencies) {
  const principal = ref<Principal | null>(null);
  const loadingSession = ref(true);
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
      applyLocale(result.data.userLocale ?? result.data.organizationDefaultLocale ?? "en");
      await loadConfiguration();
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
    try {
      const result = await api.updateUserLocale(locale);
      if (principal.value) principal.value.userLocale = result.data.userLocale;
      pageNotice.value = translate("localeSettings.userSaved");
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

  return { principal, loadingSession, loginForm, selectedOrganization, showError, refreshSession, signIn, signOut, saveLocalePreference };
}
