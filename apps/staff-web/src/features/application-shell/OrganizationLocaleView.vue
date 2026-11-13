<script setup lang="ts">
import { onMounted, ref, type Ref } from "vue";
import { api } from "../../api";
import type { SupportedLocale } from "../../i18n";

const props = defineProps<{
  busy: Ref<boolean>;
  pageNotice: Ref<string>;
  showError: (error: unknown) => void;
  translate: (key: string) => string;
  onDefaultLocaleChanged: (locale: SupportedLocale) => void;
}>();

const defaultLocale = ref<SupportedLocale>("en");
const canManage = ref(false);
const loading = ref(false);

async function load(): Promise<void> {
  loading.value = true;
  try {
    const result = await api.getOrganizationLocale();
    defaultLocale.value = result.data.defaultLocale;
    canManage.value = result.data.canManage;
  } catch (error) {
    props.showError(error);
  } finally {
    loading.value = false;
  }
}

async function save(): Promise<void> {
  if (!canManage.value || props.busy.value) return;
  props.busy.value = true;
  try {
    const result = await api.setOrganizationLocale(defaultLocale.value);
    defaultLocale.value = result.data.defaultLocale;
    props.onDefaultLocaleChanged(result.data.defaultLocale);
    props.pageNotice.value = props.translate("localeSettings.organizationSaved");
  } catch (error) {
    props.showError(error);
  } finally {
    props.busy.value = false;
  }
}

onMounted(() => { void load(); });
</script>

<template>
  <section class="workspace-section">
    <div class="section-heading">
      <p class="eyebrow">{{ $t("localeSettings.eyebrow") }}</p>
      <h2>{{ $t("localeSettings.title") }}</h2>
      <p class="muted">{{ $t("localeSettings.description") }}</p>
    </div>
    <div v-if="loading" class="loading-panel" aria-live="polite">{{ $t("app.checkingSession") }}</div>
    <div v-else class="panel">
      <label>
        {{ $t("localeSettings.organizationDefault") }}
        <select v-model="defaultLocale" :disabled="!canManage || busy.value">
          <option value="bs-BA">{{ $t("localeSettings.bosnian") }}</option>
          <option value="en">{{ $t("localeSettings.english") }}</option>
        </select>
      </label>
      <p class="fine-print">{{ canManage ? $t("localeSettings.organizationHelp") : $t("localeSettings.permissionRequired") }}</p>
      <button v-if="canManage" class="button button-primary" :disabled="busy.value" @click="save">
        {{ $t("localeSettings.saveOrganization") }}
      </button>
    </div>
  </section>
</template>
