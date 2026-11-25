<script setup lang="ts">
import { computed, onMounted, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { api, ApiError, type GuestRegistryRestorationReview, type RegistryContact, type GuestRegistryReference, type GuestRegistryProfile } from "../../api";
import { formatApiError } from "../../i18n/api-errors";

const props=defineProps<{organizationId:string;mergeId:string}>();
const emit=defineEmits<{changed:[];close:[]}>();
const {t}=useI18n();
const review=ref<GuestRegistryRestorationReview|null>(null);
const contacts=ref<RegistryContact[]>([]);
const references=ref<GuestRegistryReference[]>([]);
const selectedContacts=ref<string[]>([]);
const selectedReferences=ref<string[]>([]);
const keepRemoved=ref(false);
const confirmed=ref(false);
const submissionKey=ref("");
const busy=ref(false);
const error=ref("");
const label=(profile:GuestRegistryProfile)=>profile.displayName || `${profile.firstName} ${profile.lastName}`;
const choices=computed(()=>JSON.stringify({reviewId:review.value?.reviewId,contacts:[...selectedContacts.value].sort(),references:[...selectedReferences.value].sort(),keepRemoved:keepRemoved.value}));
watch(choices,()=>{confirmed.value=false;submissionKey.value="";});
const canApply=computed(()=>!!review.value && confirmed.value && !busy.value && (!review.value.missingReferenceCount || keepRemoved.value));
const stale=()=>new ApiError(t("apiErrors.mergeRestorationReviewStale"),412,"MERGE_RESTORATION_REVIEW_STALE");

async function run(operation:()=>Promise<void>):Promise<void> {
  busy.value=true;error.value="";
  try {await operation();}
  catch(failure) {
    if(failure instanceof ApiError && ([401,403].includes(failure.status) || failure.code==="MERGE_LABELS_CHANGED")) {
      review.value=null;contacts.value=[];references.value=[];selectedContacts.value=[];selectedReferences.value=[];
    }
    error.value=failure instanceof ApiError ? formatApiError(failure,t) : t("registry.restoration.failed");
  } finally {busy.value=false;}
}
function reload():void {
  void run(async()=>{
    review.value=null;contacts.value=[];references.value=[];selectedContacts.value=[];selectedReferences.value=[];keepRemoved.value=false;
    const current=(await api.previewGuestRegistryMergeRestoration(props.organizationId,props.mergeId)).data;
    if(current.contacts.length) {
      const directory=(await api.getGuestRegistryContacts(current.destination.personId)).data;
      if(!directory.canManage) throw new ApiError("Contact access changed",403,"FORBIDDEN");
      contacts.value=current.contacts.map(record=>{
        const contact=directory.contacts.find(item=>item.contactId===record.contactId);
        if(!contact || contact.revision!==record.revision) throw stale();
        return contact;
      });
    }
    if(current.references.some(record=>!record.missing)) {
      const directory=(await api.getGuestRegistryReferences(current.destination.personId)).data;
      if(!directory.canManage) throw new ApiError("Reference access changed",403,"FORBIDDEN");
      if(directory.profileRevision!==current.destination.revision) throw stale();
      references.value=current.references.filter(record=>!record.missing).map(record=>{
        const reference=directory.references.find(item=>item.referenceId===record.referenceId);
        if(!reference) throw stale();
        return reference;
      });
    }
    review.value=current;
  });
}
function apply():void {
  const current=review.value;
  if(!current || !canApply.value || !window.confirm(t("registry.restoration.confirm",{
    source:label(current.source),destination:label(current.destination),contacts:selectedContacts.value.length,references:selectedReferences.value.length,
    keptContacts:current.contacts.length-selectedContacts.value.length,
    keptReferences:current.references.length-current.missingReferenceCount-selectedReferences.value.length,removed:current.missingReferenceCount,
  }))) return;
  void run(async()=>{
    if(!submissionKey.value) submissionKey.value=crypto.randomUUID();
    await api.restoreGuestRegistryMergeReviewed(props.organizationId,props.mergeId,{
      reviewId:current.reviewId,returnContactIds:[...selectedContacts.value].sort(),returnReferenceIds:[...selectedReferences.value].sort(),
      keepRemovedReferences:keepRemoved.value,resolution:"return_selected_current_records",
    },submissionKey.value);
    submissionKey.value="";emit("changed");
  });
}
const contactChanged=(id:string)=>review.value?.contacts.find(record=>record.contactId===id)?.changed ?? false;
const referenceChanged=(id:string)=>review.value?.references.find(record=>record.referenceId===id)?.changed ?? false;
onMounted(reload);
</script>

<template>
  <section class="registry-restoration" aria-labelledby="registry-restoration-heading" :aria-busy="busy">
    <h4 id="registry-restoration-heading">{{ t("registry.restoration.title") }}</h4>
    <p v-if="error" role="alert" class="form-error">{{ error }}</p>
    <div class="registry-toolbar">
      <button type="button" class="button button-secondary" :disabled="busy" @click="reload">{{ t("registry.restoration.reload") }}</button>
      <button type="button" class="button button-secondary" :disabled="busy" @click="emit('close')">{{ t("common.close") }}</button>
    </div>
    <template v-if="review">
      <p>{{ t("registry.restoration.instructions") }}</p>
      <dl><dt>{{ t("registry.merge.source") }}</dt><dd>{{ label(review.source) }}</dd>
        <dt>{{ t("registry.merge.destination") }}</dt><dd>{{ label(review.destination) }}</dd></dl>
      <section v-if="review.labels.length" :aria-label="t('registry.merge.labels')">
        <h5>{{ t("registry.merge.labels") }}</h5>
        <p>{{ t("registry.restoration.labelsReturn") }}</p>
        <ul><li v-for="entry in review.labels" :key="entry.labelId">{{ entry.label }}<span v-if="entry.retired"> · {{ t("registry.labels.retired") }}</span></li></ul>
      </section>
      <h5 v-if="contacts.length">{{ t("registry.contacts.title") }}</h5>
      <ul v-if="contacts.length">
        <li v-for="contact in contacts" :key="contact.contactId">
          <label><input v-model="selectedContacts" type="checkbox" :value="contact.contactId" :disabled="busy"> {{ t("registry.restoration.returnContact",{value:contact.value}) }}</label>
          <span v-if="contactChanged(contact.contactId)" class="pill">{{ t("registry.restoration.changed") }}</span>
          <small>{{ t(`registry.contacts.consentValue.${contact.consent}`) }} · {{ t(contact.verified ? "registry.contacts.verified" : "registry.contacts.unverified") }}
            <template v-if="contact.primary"> · {{ t("registry.contacts.primary") }}</template></small>
        </li>
      </ul>
      <h5 v-if="review.references.length">{{ t("registry.references.title") }}</h5>
      <ul v-if="review.references.length">
        <li v-for="reference in references" :key="reference.referenceId">
          <label><input v-model="selectedReferences" type="checkbox" :value="reference.referenceId" :disabled="busy"> {{ t("registry.restoration.returnReference",{value:reference.value}) }}</label>
          <span v-if="referenceChanged(reference.referenceId)" class="pill">{{ t("registry.restoration.changed") }}</span>
          <small>{{ reference.source }}</small>
        </li>
        <li v-for="record in review.references.filter(item=>item.missing)" :key="record.referenceId">
          {{ t("registry.restoration.removedReference",{id:record.referenceId}) }}
        </li>
      </ul>
      <label v-if="review.missingReferenceCount"><input v-model="keepRemoved" type="checkbox" :disabled="busy"> {{ t("registry.restoration.keepRemoved") }}</label>
      <label><input v-model="confirmed" type="checkbox" :disabled="busy"> {{ t("registry.restoration.acknowledge") }}</label>
      <button type="button" class="button button-primary" :disabled="!canApply" @click="apply">{{ t("registry.restoration.apply") }}</button>
    </template>
  </section>
</template>

<style scoped>
.registry-restoration { display:grid; gap:0.75rem; border:1px solid var(--border-color, #ccd2da); padding:1rem; }
.registry-restoration li { display:grid; gap:0.3rem; margin-block:0.5rem; }
</style>
