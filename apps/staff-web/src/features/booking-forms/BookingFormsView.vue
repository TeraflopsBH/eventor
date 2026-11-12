<script setup lang="ts">
import { computed, reactive } from "vue";
import { useI18n } from "vue-i18n";
import type { useBookingForms } from "./useBookingForms";
const props = defineProps<{ workspace: ReturnType<typeof useBookingForms> & { busy: { value: boolean } } }>();
const { t } = useI18n();
const w = reactive(props.workspace);
const locales = [{ value: "bs-BA" as const, label: "Bosanski" }, { value: "en" as const, label: "English" }];
const previewName = computed(() => w.schema.contentTranslations?.[w.previewLocale]?.formName || w.selectedForm?.name || "");
function setType(type: string): void {
  const field = w.selectedField;
  if (!field) return;
  field.type = type as typeof field.type;
  if (type === "select" || type === "multiselect") field.options ??= [{ value: "option", label: "Option" }];
  else delete field.options;
  w.markDirty();
}
</script>

<template>
<section class="workspace-section">
  <div class="section-heading">
    <div><p class="eyebrow">{{ t("bookingForms.eyebrow") }}</p><h2>{{ t("bookingForms.title") }}</h2><p class="muted">{{ t("bookingForms.description") }}</p></div>
    <button class="button button-quiet" :disabled="w.busy" @click="w.open">{{ t("bookingForms.refresh") }}</button>
  </div>
  <div class="panel booking-form-create">
    <h3>{{ t("bookingForms.createTitle") }}</h3>
    <div class="form-grid">
      <label>{{ t("bookingForms.code") }}<input v-model="w.createForm.code" maxlength="80" /></label>
      <label>{{ t("bookingForms.name") }}<input v-model="w.createForm.name" maxlength="250" /></label>
      <label>{{ t("bookingForms.baseLanguage") }}<select v-model="w.createForm.locale"><option v-for="item in locales" :key="item.value" :value="item.value">{{ item.label }}</option></select></label>
    </div>
    <button class="button button-primary" :disabled="w.busy" @click="w.create">{{ t("bookingForms.create") }}</button>
  </div>
  <div class="booking-form-layout">
    <aside class="panel booking-form-list">
      <h3>{{ t("bookingForms.forms") }}</h3>
      <p v-if="!w.forms.length" class="muted">{{ t("bookingForms.empty") }}</p>
      <button v-for="form in w.forms" :key="form.formId" class="booking-form-list-item" :class="{ active: form.formId === w.selectedFormId }" @click="w.selectForm(form.formId)">
        <strong>{{ form.name }}</strong><span>{{ form.formCode }}</span><small>{{ form.revisions.length }} · {{ form.revisions[0]?.state ?? form.status }}</small>
      </button>
    </aside>
    <div v-if="w.selectedForm" class="booking-form-editor">
      <section class="panel">
        <div class="section-heading compact"><div><p class="eyebrow">{{ w.selectedForm.formCode }}</p><h3>{{ w.selectedForm.name }}</h3><p class="muted">{{ t("bookingForms.revision", { number: w.latestRevision?.revisionNumber ?? 0 }) }} · {{ w.latestRevision?.state }}</p></div>
          <button v-if="!w.editable" class="button button-secondary" :disabled="w.busy" @click="w.createRevision">{{ t("bookingForms.newRevision") }}</button>
        </div>
        <div class="form-grid">
          <label>{{ t("bookingForms.baseLanguage") }}<select v-model="w.baseLocale" :disabled="!w.editable" @change="w.markDirty"><option v-for="item in locales" :key="item.value" :value="item.value">{{ item.label }}</option></select></label>
          <label>{{ t("bookingForms.formName") }}<input :value="w.translation(w.baseLocale).formName || w.selectedForm.name" :disabled="!w.editable" @input="w.translation(w.baseLocale).formName = ($event.target as HTMLInputElement).value; w.markDirty()" /></label>
        </div>
        <div class="booking-form-actions">
          <span class="muted">{{ w.dirty ? t("bookingForms.unsaved") : t("bookingForms.savedState") }}</span>
          <button class="button button-primary" :disabled="w.busy || !w.editable || !w.dirty" @click="w.save">{{ t("bookingForms.saveDraft") }}</button>
          <button class="button button-secondary" :disabled="w.busy || !w.editable || w.dirty || !w.schema.fields.length" @click="w.publish">{{ t("bookingForms.publish") }}</button>
        </div>
      </section>
      <section class="panel">
        <div class="section-heading compact"><h3>{{ t("bookingForms.fields") }} ({{ w.schema.fields.length }}/100)</h3><button class="button button-quiet" :disabled="!w.editable || w.schema.fields.length >= 100" @click="w.addField">{{ t("bookingForms.addField") }}</button></div>
        <div class="booking-form-field-list">
          <button v-for="field in w.schema.fields" :key="field.code" class="booking-form-field-chip" :class="{ active: field.code === w.selectedFieldCode }" @click="w.selectedFieldCode = field.code">{{ field.label || field.code }} <small>{{ field.type }}</small></button>
          <p v-if="!w.schema.fields.length" class="muted">{{ t("bookingForms.noFields") }}</p>
        </div>
        <template v-if="w.selectedField">
          <div class="form-grid">
            <label>{{ t("bookingForms.fieldCode") }}<input v-model="w.selectedField.code" pattern="[a-z][a-z0-9_]{0,79}" :disabled="!w.editable" @input="w.markDirty" /></label>
            <label>{{ t("bookingForms.fieldType") }}<select :value="w.selectedField.type" :disabled="!w.editable" @change="setType(($event.target as HTMLSelectElement).value)"><option v-for="type in ['text','textarea','email','phone','number','date','datetime','time','select','multiselect','checkbox']" :key="type" :value="type">{{ type }}</option></select></label>
            <label>{{ t("bookingForms.label") }}<input v-model="w.selectedField.label" :disabled="!w.editable" @input="w.markDirty" /></label>
            <label class="checkbox-label"><input v-model="w.selectedField.required" type="checkbox" :disabled="!w.editable" @change="w.markDirty" />{{ t("bookingForms.required") }}</label>
            <label v-if="['text','textarea','email','phone'].includes(w.selectedField.type)">{{ t("bookingForms.minLength") }}<input v-model.number="w.selectedField.minLength" type="number" min="0" max="5000" :disabled="!w.editable" @input="w.markDirty" /></label>
            <label v-if="['text','textarea','email','phone'].includes(w.selectedField.type)">{{ t("bookingForms.maxLength") }}<input v-model.number="w.selectedField.maxLength" type="number" min="1" max="5000" :disabled="!w.editable" @input="w.markDirty" /></label>
            <label v-if="w.selectedField.type === 'number'">{{ t("bookingForms.minimum") }}<input v-model.number="w.selectedField.min" type="number" :disabled="!w.editable" @input="w.markDirty" /></label>
            <label v-if="w.selectedField.type === 'number'">{{ t("bookingForms.maximum") }}<input v-model.number="w.selectedField.max" type="number" :disabled="!w.editable" @input="w.markDirty" /></label>
            <label v-if="w.selectedField.type === 'number'" class="checkbox-label"><input v-model="w.selectedField.integer" type="checkbox" :disabled="!w.editable" @change="w.markDirty" />{{ t("bookingForms.integer") }}</label>
            <label v-if="w.selectedField.type === 'multiselect'">{{ t("bookingForms.minItems") }}<input v-model.number="w.selectedField.minItems" type="number" min="0" :disabled="!w.editable" @input="w.markDirty" /></label>
            <label v-if="w.selectedField.type === 'multiselect'">{{ t("bookingForms.maxItems") }}<input v-model.number="w.selectedField.maxItems" type="number" min="1" :disabled="!w.editable" @input="w.markDirty" /></label>
          </div>
          <div v-if="['select','multiselect'].includes(w.selectedField.type)" class="option-editor">
            <div class="section-heading compact"><h4>{{ t("bookingForms.options") }}</h4><button class="button button-quiet" :disabled="!w.editable" @click="w.addOption(w.selectedField!)">{{ t("bookingForms.addOption") }}</button></div>
            <div v-for="(option, index) in w.selectedField.options || []" :key="option.value" class="form-grid option-row">
              <label>{{ t("bookingForms.optionValue") }}<input v-model="option.value" :disabled="!w.editable" @input="w.markDirty" /></label>
              <label>{{ t("bookingForms.optionLabel") }}<input v-model="option.label" :disabled="!w.editable" @input="w.markDirty" /></label>
              <button class="button button-quiet" :disabled="!w.editable" @click="w.selectedField!.options!.splice(index,1); w.markDirty()">{{ t("bookingForms.remove") }}</button>
            </div>
          </div>
          <button class="button button-danger" :disabled="!w.editable" @click="w.removeField(w.selectedField.code)">{{ t("bookingForms.removeField") }}</button>
        </template>
      </section>
      <section class="panel">
        <div class="section-heading compact"><div><h3>{{ t("bookingForms.translations") }}</h3><p class="muted">{{ t("bookingForms.translationHelp") }}</p></div></div>
        <div v-for="locale in locales" :key="locale.value" class="translation-section">
          <h4>{{ locale.label }} <small>{{ w.completeness(locale.value).complete }}/{{ w.completeness(locale.value).total }}</small></h4>
          <label>{{ t("bookingForms.translatedFormName") }}<input :value="w.translation(locale.value).formName" :disabled="!w.editable" @input="w.translation(locale.value).formName = ($event.target as HTMLInputElement).value; w.markDirty()" /></label>
          <template v-for="field in w.schema.fields" :key="field.code">
            <div class="form-grid">
              <label>{{ field.code }} · {{ t("bookingForms.label") }}<input :value="w.fieldText(locale.value, field, 'label')" :disabled="!w.editable" @input="w.setFieldText(locale.value,field,'label',($event.target as HTMLInputElement).value)" /></label>
              <label>{{ t("bookingForms.description") }}<input :value="w.fieldText(locale.value, field, 'description')" :disabled="!w.editable" @input="w.setFieldText(locale.value,field,'description',($event.target as HTMLInputElement).value)" /></label>
              <label>{{ t("bookingForms.helpText") }}<input :value="w.fieldText(locale.value, field, 'helpText')" :disabled="!w.editable" @input="w.setFieldText(locale.value,field,'helpText',($event.target as HTMLInputElement).value)" /></label>
              <label>{{ t("bookingForms.placeholder") }}<input :value="w.fieldText(locale.value, field, 'placeholder')" :disabled="!w.editable" @input="w.setFieldText(locale.value,field,'placeholder',($event.target as HTMLInputElement).value)" /></label>
              <template v-for="option in field.options || []" :key="option.value"><label>{{ option.value }}<input :value="w.optionText(locale.value,field,option.value,'')" :disabled="!w.editable" @input="w.setOptionText(locale.value,field,option.value,($event.target as HTMLInputElement).value)" /></label></template>
            </div>
          </template>
        </div>
      </section>
      <section class="panel">
        <div class="section-heading compact"><div><h3>{{ t("bookingForms.preview") }}</h3><p class="muted">{{ t("bookingForms.previewHelp") }}</p></div><select v-model="w.previewLocale"><option v-for="item in locales" :key="item.value" :value="item.value">{{ item.label }}</option></select></div>
        <div class="booking-form-preview"><h3>{{ previewName }}</h3><div v-for="field in w.schema.fields" :key="field.code" class="preview-field"><label>{{ w.previewFieldLabel(w.previewLocale,field) }} <span v-if="field.required">*</span></label><textarea v-if="field.type === 'textarea'" disabled rows="2"></textarea><select v-else-if="field.type === 'select' || field.type === 'multiselect'" disabled><option>{{ t("bookingForms.previewChoice") }}</option><option v-for="option in field.options || []" :key="option.value">{{ w.previewOptionLabel(w.previewLocale,field,option) }}</option></select><input v-else-if="field.type !== 'checkbox'" :type="field.type === 'email' ? 'email' : field.type === 'number' ? 'number' : ['date','datetime','time'].includes(field.type) ? field.type === 'datetime' ? 'datetime-local' : field.type : field.type === 'phone' ? 'tel' : 'text'" disabled /><label v-else><input type="checkbox" disabled /> {{ w.previewFieldLabel(w.previewLocale,field) }}</label></div></div>
      </section>
    </div>
    <div v-else class="panel muted">{{ t("bookingForms.selectForm") }}</div>
  </div>
</section>
</template>
