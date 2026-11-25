<script setup lang="ts">
import {nextTick,onMounted,ref} from "vue";
import {useI18n} from "vue-i18n";
import {api,ApiError,type StaffCollaborationGrant} from "../../api";
import {formatApiError} from "../../i18n/api-errors";
import {formatDateTime} from "../../i18n/format";
type Review=StaffCollaborationGrant & {projection:Record<string,unknown>;reviewFingerprint:string};
const props=defineProps<{organizationId:string}>();
const {t,locale}=useI18n();
const heading=ref<HTMLElement|null>(null),reviewHeading=ref<HTMLElement|null>(null);
const grants=ref<StaffCollaborationGrant[]|null>(null),review=ref<Review|null>(null);
const offset=ref(0),next=ref<number|null>(null),busy=ref(false),error=ref(""),notice=ref(""),reason=ref("");
const incoming=(grant:StaffCollaborationGrant)=>grant.granteeOrganizationId===props.organizationId;
const partnerId=(grant:StaffCollaborationGrant)=>incoming(grant)?grant.grantorOrganizationId:grant.granteeOrganizationId;
const partner=(grant:StaffCollaborationGrant)=>(incoming(grant)?grant.grantorDisplayName:grant.granteeDisplayName)??t("collaborationGrants.reference",{id:partnerId(grant)});
async function run(operation:()=>Promise<void>){
 if(busy.value)return;
 busy.value=true;error.value="";notice.value="";
 try{await operation();}catch(failure){
  if(failure instanceof ApiError && [401,403].includes(failure.status)){grants.value=null;review.value=null;reason.value="";}
  if(failure instanceof ApiError && failure.status===409){review.value=null;reason.value="";}
  error.value=failure instanceof ApiError?formatApiError(failure,t):t("collaborationGrants.failed");
  if(failure instanceof ApiError && failure.status===409)error.value+=` ${t("collaborationGrants.reviewAgain")}`;
 }finally{busy.value=false;}
}
async function loadList(page=0){const {data}=await api.listCollaborationGrants(props.organizationId,page);grants.value=data.grants;offset.value=page;next.value=data.nextOffset;}
function reload(page=0){review.value=null;reason.value="";void run(()=>loadList(page));}
function open(grantId:string){void run(async()=>{
 review.value=null;reason.value="";review.value=(await api.readCollaborationGrant(grantId)).data;await nextTick();reviewHeading.value?.focus();
});}
async function refreshAfterAction(grantId:string){
 const [listed,details]=await Promise.all([api.listCollaborationGrants(props.organizationId,offset.value),api.readCollaborationGrant(grantId)]);
 grants.value=listed.data.grants;next.value=listed.data.nextOffset;review.value=details.data;reason.value="";
}
function accept(){
 const selected=review.value;
 if(!selected?.canAccept || !selected.reviewFingerprint || busy.value || !window.confirm(t("collaborationGrants.acceptConfirm",{partner:partner(selected)})))return;
 void run(async()=>{await api.acceptCollaborationGrant(selected.grantId,selected.reviewFingerprint);await refreshAfterAction(selected.grantId);notice.value=t("collaborationGrants.accepted");});
}
function revoke(){
 const selected=review.value;
 if(!selected?.canRevoke || reason.value.trim().length<3 || busy.value || !window.confirm(t("collaborationGrants.revokeConfirm",{partner:partner(selected)})))return;
 const explanation=reason.value.trim();
 void run(async()=>{await api.revokeCollaborationGrant(selected.grantId,explanation);await refreshAfterAction(selected.grantId);notice.value=t("collaborationGrants.revoked");});
}
onMounted(()=>{heading.value?.focus();reload();});
</script>
<template>
 <section id="collaboration-grant-workspace" class="collaboration-grants panel" aria-labelledby="collaboration-heading" :aria-busy="busy">
  <h3 id="collaboration-heading" ref="heading" tabindex="-1">{{t("collaborationGrants.title")}}</h3>
  <p>{{t("collaborationGrants.help")}}</p>
  <p v-if="error" role="alert" class="form-error">{{error}}</p><p v-if="notice" role="status">{{notice}}</p>
  <button type="button" class="button button-secondary" :disabled="busy" @click="reload()">{{t("collaborationGrants.reload")}}</button>
  <template v-if="grants">
   <p v-if="!grants.length">{{t("collaborationGrants.empty")}}</p>
   <ul v-else class="grant-list" :aria-label="t('collaborationGrants.list')">
    <li v-for="grant in grants" :key="grant.grantId" :data-grant-id="grant.grantId" class="grant-card">
     <h4>{{grant.purpose}}</h4><p>{{t(incoming(grant)?"collaborationGrants.incoming":"collaborationGrants.outgoing")}} · {{partner(grant)}}</p>
     <p>{{t(`collaborationGrants.statuses.${grant.status}`)}} · {{t(`collaborationGrants.scopes.${grant.scopeKind}`)}}</p>
     <button type="button" class="button button-secondary" :disabled="busy" :aria-label="t('collaborationGrants.reviewNamed',{purpose:grant.purpose})" @click="open(grant.grantId)">{{t("collaborationGrants.review")}}</button>
    </li>
   </ul>
   <div v-if="offset || next!==null" class="toolbar">
    <button type="button" class="button button-secondary" :disabled="busy || offset===0" @click="reload(Math.max(0,offset-50))">{{t("registry.previous")}}</button>
    <button type="button" class="button button-secondary" :disabled="busy || next===null" @click="reload(next??0)">{{t("registry.next")}}</button>
   </div>
  </template>
  <section v-if="review" class="grant-review" aria-labelledby="grant-review-heading">
   <h4 id="grant-review-heading" ref="reviewHeading" tabindex="-1">{{t("collaborationGrants.reviewTitle",{purpose:review.purpose})}}</h4>
   <dl>
    <dt>{{t("collaborationGrants.partner")}}</dt><dd>{{partner(review)}}</dd>
    <dt>{{t("collaborationGrants.partnerReference")}}</dt><dd><code>{{partnerId(review)}}</code></dd>
    <dt>{{t("collaborationGrants.scope")}}</dt><dd>{{t(`collaborationGrants.scopes.${review.scopeKind}`)}} · <code>{{review.bookingId??review.spaceId??review.venueId}}</code></dd>
    <dt>{{t("collaborationGrants.state")}}</dt><dd>{{t(`collaborationGrants.statuses.${review.status}`)}}</dd>
    <dt>{{t("collaborationGrants.validFrom")}}</dt><dd>{{formatDateTime(review.validFrom,locale)}}</dd>
    <dt>{{t("collaborationGrants.validUntil")}}</dt><dd>{{review.validUntil?formatDateTime(review.validUntil,locale):t("collaborationGrants.noExpiry")}}</dd>
    <dt>{{t("collaborationGrants.effective")}}</dt><dd>{{t(review.effective?"collaborationGrants.yes":"collaborationGrants.no")}}</dd>
    <template v-if="review.acceptedAt"><dt>{{t("collaborationGrants.acceptedAt")}}</dt><dd>{{formatDateTime(review.acceptedAt,locale)}}</dd></template>
    <template v-if="review.revokedAt"><dt>{{t("collaborationGrants.revokedAt")}}</dt><dd>{{formatDateTime(review.revokedAt,locale)}}</dd></template>
   </dl>
   <h5>{{t("collaborationGrants.actionsTitle")}}</h5>
   <ul><li v-for="action in review.allowedActions" :key="action">{{action==='booking.event.link'?t("collaborationGrants.bookingLinkAction"):action}}</li></ul>
   <details open><summary>{{t("collaborationGrants.configuration")}}</summary><pre>{{JSON.stringify(review.projection,null,2)}}</pre></details>
   <p class="fine-print">{{t("collaborationGrants.namesHelp")}}</p>
   <button v-if="review.canAccept && review.reviewFingerprint" type="button" class="button button-primary" :disabled="busy" @click="accept">{{t("collaborationGrants.accept")}}</button>
   <form v-if="review.canRevoke" @submit.prevent="revoke">
    <label for="grant-revocation-reason">{{t("collaborationGrants.reason")}}</label><input type="text" id="grant-revocation-reason" v-model="reason" required minlength="3" maxlength="2000" :disabled="busy" />
    <button type="submit" class="button button-secondary" :disabled="busy || reason.trim().length<3">{{t("collaborationGrants.revoke")}}</button>
   </form>
  </section>
 </section>
</template>
<style scoped>
.collaboration-grants {display:grid;grid-template-columns:minmax(0,1fr);gap:.75rem;min-width:0;overflow-wrap:anywhere;}
.grant-list {list-style:none;margin:0;padding:0;display:grid;gap:.75rem;}
.grant-card,.grant-review {padding:1rem;border:1px solid var(--border);border-radius:9px;min-width:0;}
.grant-review {display:grid;gap:.75rem;}
dl {display:grid;grid-template-columns:minmax(0,1fr) minmax(0,2fr);gap:.6rem;margin:0;}
dd {margin:0;min-width:0;}dt {color:var(--muted);}
pre {white-space:pre-wrap;overflow-wrap:anywhere;word-break:break-word;}
form {display:grid;gap:.75rem;min-width:0;}
.toolbar {display:flex;flex-wrap:wrap;gap:.6rem;}
h3:focus,h4:focus {outline:2px solid var(--accent);outline-offset:3px;}
@media(max-width:600px){dl {grid-template-columns:minmax(0,1fr);}dd {margin-bottom:.5rem;}}
</style>
