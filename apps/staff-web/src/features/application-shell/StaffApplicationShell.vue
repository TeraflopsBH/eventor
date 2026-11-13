<script setup lang="ts">
import { computed, type Ref, type WritableComputedRef } from "vue";
import type { SupportedLocale } from "../../i18n";
import type { useStaffSession } from "./useStaffSession";

type Workspace = ReturnType<typeof useStaffSession> & {
  busy: Ref<boolean>;
  pageError: Ref<string>;
  pageNotice: Ref<string>;
  activeTab: Ref<"delivery" | "campaign" | "inquiries" | "approvals" | "prices" | "cancellations" | "taxes" | "settings">;
  locale: WritableComputedRef<string>;
  localeOptions: Array<{ value: SupportedLocale; label: string }>;
  openInquiryWorkspace: () => Promise<void>;
  openBookingApprovalPolicies: () => Promise<void>;
  openBookingPriceLists: () => Promise<void>;
  openBookingCancellationPolicies: () => Promise<void>;
  openBookingTaxProfiles: () => Promise<void>;
};

const props = defineProps<{ workspace: Workspace }>();
const {
  principal, loadingSession, loginForm, selectedOrganization, signIn, signOut,
  busy, pageError, pageNotice, activeTab, locale, localeOptions,
  openInquiryWorkspace, openBookingApprovalPolicies, openBookingPriceLists,
  openBookingCancellationPolicies, openBookingTaxProfiles,
} = props.workspace;
const selectedLocale = computed({
  get: () => locale.value as SupportedLocale,
  set: (value: SupportedLocale) => {
    locale.value = value;
    void props.workspace.saveLocalePreference(value);
  },
});
</script>

<template>
<main class="app-shell">
    <header class="topbar">
      <a class="brand" href="/"  :aria-label="$t('app.staffHome')">
        <span class="brand-mark">E</span>
        <span>EVENTOR <small>{{ $t("app.staffWorkspace") }}</small></span>
      </a>
      <label class="locale-picker">{{ $t("app.language") }} <select v-model="selectedLocale"><option v-for="option in localeOptions" :key="option.value" :value="option.value">{{ option.label }}</option></select></label>
      <button v-if="principal?.userLocale" class="button button-quiet" :disabled="busy" @click="props.workspace.useOrganizationLocalePreference">{{ $t("localeSettings.useOrganization") }}</button>
      <div v-if="principal" class="account">
        <div class="account-copy">
          <strong>{{ selectedOrganization }}</strong>
          <span>{{ $t("app.authenticatedSession") }}</span>
        </div>
        <button class="button button-quiet" :disabled="busy" @click="signOut">{{ $t("app.signOut") }}</button>
      </div>
    </header>

    <section v-if="loadingSession" class="loading-panel" aria-live="polite">
      <span class="spinner"></span> {{ $t("app.checkingSession") }}
    </section>

    <section v-else-if="!principal" class="login-layout">
      <div class="intro-panel">
        <p class="eyebrow">{{ $t("auth.platformEyebrow") }}</p>
        <h1>{{ $t("auth.headline") }}</h1>
        <p class="muted">{{ $t("auth.description") }}</p>
        <div class="security-note"><span class="status-dot"></span> {{ $t("auth.security") }}</div>
      </div>
      <form class="panel login-panel" @submit.prevent="signIn">
        <p class="eyebrow">{{ $t("auth.staffAccess") }}</p>
        <h2>{{ $t("auth.signIn") }}</h2>
        <label>{{ $t("auth.email") }}<input v-model="loginForm.email" type="email" autocomplete="username" required maxlength="320" /></label>
        <label>{{ $t("auth.organization") }}<input v-model="loginForm.organizationSlug" autocomplete="organization" required minlength="2" maxlength="80" /></label>
        <label>{{ $t("auth.password") }}<input v-model="loginForm.password" type="password" autocomplete="current-password" required minlength="12" maxlength="1024" /></label>
        <button class="button button-primary full-width" type="submit" :disabled="busy">
          {{ busy ? $t("auth.signingIn") : $t("auth.signInSecurely") }}
        </button>
        <p class="fine-print">{{ $t("auth.passwordNote") }}</p>
      </form>
    </section>

    <template v-else>
      <section class="welcome-row">
        <div>
          <p class="eyebrow">{{ $t("workspace.organization") }}</p>
          <h1>{{ $t("workspace.overview") }}</h1>
          <p class="muted">{{ $t("workspace.description") }}</p>
        </div>
        <div class="session-chip"><span class="status-dot"></span> {{ $t("workspace.active") }}</div>
      </section>

      <nav class="tabs" :aria-label="$t('app.workspaceSections')">
        <button :class="{ active: activeTab === 'delivery' }" @click="activeTab = 'delivery'">{{ $t("navigation.delivery") }}</button>
        <button :class="{ active: activeTab === 'campaign' }" @click="activeTab = 'campaign'">{{ $t("navigation.campaigns") }}</button>
        <button :class="{ active: activeTab === 'inquiries' }" @click="openInquiryWorkspace">{{ $t("navigation.inquiries") }}</button>
        <button :class="{ active: activeTab === 'approvals' }" @click="openBookingApprovalPolicies">{{ $t("navigation.approvals") }}</button>
        <button :class="{ active: activeTab === 'prices' }" @click="openBookingPriceLists">{{ $t("navigation.prices") }}</button>
        <button :class="{ active: activeTab === 'cancellations' }" @click="openBookingCancellationPolicies">{{ $t("navigation.cancellations") }}</button>
        <button :class="{ active: activeTab === 'taxes' }" @click="openBookingTaxProfiles">{{ $t("navigation.taxes") }}</button>
        <button :class="{ active: activeTab === 'settings' }" @click="activeTab = 'settings'">{{ $t("navigation.settings") }}</button>
      </nav>

      
      <slot />
    </template>

    <div v-if="pageError" class="message message-error" role="alert">{{ pageError }}</div>
    <div v-if="pageNotice" class="message message-success" role="status">{{ pageNotice }}</div>

    <footer class="footer"><span>{{ $t("app.footerBrand") }}</span><span>{{ $t("app.footerDescription") }}</span></footer>
  </main>
</template>
