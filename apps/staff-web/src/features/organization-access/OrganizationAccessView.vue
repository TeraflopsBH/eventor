<script setup lang="ts">
import { computed, onMounted, reactive, ref } from "vue";
import { useI18n } from "vue-i18n";
import {
  api, ApiError, type OrganizationAccessGrant, type OrganizationAccessMember,
  type OrganizationAccessRole, type OrganizationPermission,
} from "../../api";
import { formatApiError } from "../../i18n/api-errors";

const props = defineProps<{ organizationId: string }>();
const { t, locale } = useI18n();
const roles = ref<OrganizationAccessRole[]>([]);
const permissions = ref<OrganizationPermission[]>([]);
const members = ref<OrganizationAccessMember[]>([]);
const offset = ref(0);
const nextOffset = ref<number | null>(null);
const loaded = ref(false);
const busy = ref(false);
const error = ref("");
const showRoleForm = ref(false);
const grantMember = ref<OrganizationAccessMember | null>(null);
const events = ref<{ eventId: string; eventCode: string; title: string }[]>([]);
const grantDraft = reactive({ roleId: "", eventId: "" });
const eventRoles = computed(() => roles.value.filter((role) => role.scope === "event" && !role.retiredAt));
const notice = ref("");
const permissionFilter = ref("");
const roleDraft = reactive({ code: "", name: "", description: "", permissionCodes: [] as string[] });
const eventPermissions = computed(() => permissions.value.filter((permission) => permission.scope === "event"));
const filteredEventPermissions = computed(() => {
  const query = permissionFilter.value.trim().toLowerCase();
  return eventPermissions.value.filter((permission) =>
    permission.code.toLowerCase().includes(query) || permission.description.toLowerCase().includes(query));
});
const permissionByCode = computed(() => new Map(permissions.value.map((item) => [item.code, item])));

function describeScope(grant: OrganizationAccessGrant): string {
  const scope = t(`organizationAccess.scopes.${grant.scope}`);
  const target = grant.scopeName ?? grant.scopeId;
  return target ? t("organizationAccess.scopedTo", { scope, target }) : scope;
}

function expiry(value: string): string {
  const date = new Intl.DateTimeFormat(locale.value, { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
  return t("organizationAccess.expires", { date });
}

function showFailure(failure: unknown): void {
  if (failure instanceof ApiError && [401, 403].includes(failure.status)) {
    members.value = [];
    roles.value = [];
    permissions.value = [];
    loaded.value = false;
    showRoleForm.value = false;
    grantMember.value = null;
    notice.value = "";
  }
  error.value = failure instanceof ApiError ? formatApiError(failure, t) : t("organizationAccess.failed");
}

async function load(page: number): Promise<void> {
  if (busy.value) return;
  busy.value = true;
  error.value = "";
  try {
    const membersRequest = api.listOrganizationAccessMembers(props.organizationId, page);
    if (loaded.value) {
      const { data } = await membersRequest;
      members.value = data.members;
      nextOffset.value = data.nextOffset;
    } else {
      const [membersResult, roleResult, permissionResult] = await Promise.all([
        membersRequest, api.listOrganizationAccessRoles(props.organizationId), api.listOrganizationPermissions(props.organizationId),
      ]);
      members.value = membersResult.data.members;
      nextOffset.value = membersResult.data.nextOffset;
      roles.value = roleResult.data;
      permissions.value = permissionResult.data;
      loaded.value = true;
    }
    offset.value = page;
  } catch (failure) {
    showFailure(failure);
  } finally {
    busy.value = false;
  }
}

async function createRole(): Promise<void> {
  if (busy.value || !roleDraft.name.trim() || !roleDraft.permissionCodes.length) return;
  busy.value = true;
  error.value = "";
  notice.value = "";
  try {
    await api.createOrganizationEventRole(props.organizationId, {
      code: roleDraft.code.trim().toUpperCase(), name: roleDraft.name.trim(),
      description: roleDraft.description.trim(), permissionCodes: roleDraft.permissionCodes,
    });
    notice.value = t("organizationAccess.roleCreated");
    showRoleForm.value = false;
    Object.assign(roleDraft, { code: "", name: "", description: "", permissionCodes: [] });
    permissionFilter.value = "";
    roles.value = (await api.listOrganizationAccessRoles(props.organizationId)).data;
  } catch (failure) {
    showFailure(failure);
  } finally {
    busy.value = false;
  }
}

async function retireRole(role: OrganizationAccessRole): Promise<void> {
  if (busy.value || !window.confirm(t("organizationAccess.confirmRetire", { role: role.name }))) return;
  busy.value = true;
  error.value = "";
  notice.value = "";
  try {
    await api.retireOrganizationEventRole(props.organizationId, role.roleId);
    roles.value = (await api.listOrganizationAccessRoles(props.organizationId)).data;
    notice.value = t("organizationAccess.roleRetired");
  } catch (failure) {
    showFailure(failure);
  } finally {
    busy.value = false;
  }
}

async function changeMemberAccess(member: OrganizationAccessMember): Promise<void> {
  if (busy.value || !["active", "suspended"].includes(member.status)) return;
  const status = member.status === "active" ? "suspended" : "active";
  const confirmation = status === "suspended" ? "organizationAccess.confirmSuspend" : "organizationAccess.confirmRestore";
  if (!window.confirm(t(confirmation, { member: member.displayName }))) return;
  busy.value = true;
  error.value = "";
  notice.value = "";
  try {
    await api.setOrganizationMemberAccess(props.organizationId, member.membershipId, status, member.revision);
    const { data } = await api.listOrganizationAccessMembers(props.organizationId, offset.value);
    members.value = data.members;
    nextOffset.value = data.nextOffset;
    grantMember.value = null;
    notice.value = t(status === "suspended" ? "organizationAccess.memberSuspended" : "organizationAccess.memberRestored");
  } catch (failure) {
    showFailure(failure);
    if (failure instanceof ApiError && failure.status === 401) window.location.reload();
  } finally {
    busy.value = false;
  }
}

async function openGrant(member: OrganizationAccessMember): Promise<void> {
  busy.value = true;
  error.value = "";
  notice.value = "";
  grantMember.value = null;
  try {
    events.value = (await api.listOrganizationAccessEvents(props.organizationId)).data;
    Object.assign(grantDraft, { roleId: "", eventId: "" });
    grantMember.value = member;
  } catch (failure) {
    showFailure(failure);
  } finally {
    busy.value = false;
  }
}

async function changeGrant(member: OrganizationAccessMember, grant?: OrganizationAccessGrant): Promise<void> {
  if (busy.value) return;
  if (grant && !window.confirm(t("organizationAccess.confirmRevoke", { role: grant.roleName, member: member.displayName }))) return;
  busy.value = true;
  error.value = "";
  notice.value = "";
  try {
    if (grant) {
      await api.revokeMemberEventRole(props.organizationId, member.membershipId, grant.grantId);
    } else {
      await api.grantMemberEventRole(props.organizationId, member.membershipId, grantDraft.roleId, grantDraft.eventId);
    }
    const { data } = await api.listOrganizationAccessMembers(props.organizationId, offset.value);
    members.value = data.members;
    nextOffset.value = data.nextOffset;
    grantMember.value = null;
    notice.value = t(grant ? "organizationAccess.grantRevoked" : "organizationAccess.grantSaved");
  } catch (failure) {
    showFailure(failure);
  } finally {
    busy.value = false;
  }
}

onMounted(() => { void load(0); });
</script>

<template>
  <section class="panel organization-access" aria-labelledby="organization-access-heading" :aria-busy="busy">
    <h3 id="organization-access-heading">{{ t("organizationAccess.title") }}</h3>
    <p v-if="error" class="form-error" role="alert">{{ error }}</p>
    <p v-if="notice" role="status">{{ notice }}</p>
    <button v-if="error" class="button button-secondary" type="button" :disabled="busy" @click="load(offset)">
      {{ t("organizationAccess.retry") }}
    </button>
    <template v-if="loaded">
      <h4>{{ t("organizationAccess.members") }}</h4>
      <p v-if="!members.length">{{ t("organizationAccess.noMembers") }}</p>
      <div v-else class="table-scroll">
        <table class="data-table">
          <thead>
            <tr>
              <th scope="col">{{ t("registry.displayName") }}</th>
              <th scope="col">{{ t("organizationAccess.status") }}</th>
              <th scope="col">{{ t("organizationAccess.activeGrants") }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="member in members" :key="member.membershipId">
              <th scope="row">{{ member.displayName }}</th>
              <td>
                <span>{{ t(`organizationAccess.statuses.${member.status}`) }}</span>
                <button v-if="['active','suspended'].includes(member.status)" class="button button-secondary" type="button"
                  :disabled="busy" @click="changeMemberAccess(member)">
                  {{ t(member.status === 'active' ? "organizationAccess.suspendMember" : "organizationAccess.restoreMember") }}
                </button>
              </td>
              <td>
                <span v-if="!member.grants.length">{{ t("organizationAccess.noGrants") }}</span>
                <ul v-else>
                  <li v-for="grant in member.grants" :key="grant.grantId">
                    {{ grant.roleName }} · {{ describeScope(grant) }}
                    <small v-if="grant.expiresAt"> · {{ expiry(grant.expiresAt) }}</small>
                    <button v-if="grant.scope === 'event'" class="button button-secondary" type="button" :disabled="busy"
                      @click="changeGrant(member, grant)">{{ t("organizationAccess.revokeGrant") }}</button>
                  </li>
                </ul>
                <button v-if="member.status === 'active' && eventRoles.length" class="button button-secondary" type="button"
                  :disabled="busy" @click="openGrant(member)">{{ t("organizationAccess.assignRole") }}</button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <div v-if="offset > 0 || nextOffset !== null" class="access-pagination">
        <button class="button button-secondary" type="button" :disabled="busy || offset === 0" @click="load(offset - 50)">
          {{ t("registry.previous") }}
        </button>
        <button class="button button-secondary" type="button" :disabled="busy || nextOffset === null" @click="load(nextOffset ?? 0)">
          {{ t("registry.next") }}
        </button>
      </div>
      <form v-if="grantMember" class="event-role-form" @submit.prevent="changeGrant(grantMember)">
        <h4>{{ t("organizationAccess.assignFor", { member: grantMember.displayName }) }}</h4>
        <label for="member-event-role">{{ t("organizationAccess.roleName") }}</label>
          <select id="member-event-role" v-model="grantDraft.roleId" required :disabled="busy">
            <option value="" disabled>{{ t("organizationAccess.chooseRole") }}</option>
            <option v-for="role in eventRoles" :key="role.roleId" :value="role.roleId">{{ role.name }}</option>
          </select>
        <label for="member-event-scope">{{ t("organizationAccess.event") }}</label>
          <select id="member-event-scope" v-model="grantDraft.eventId" required :disabled="busy">
            <option value="" disabled>{{ t("organizationAccess.chooseEvent") }}</option>
            <option v-for="event in events" :key="event.eventId" :value="event.eventId">{{ event.title }} ({{ event.eventCode }})</option>
          </select>
        <button class="button button-primary" type="submit" :disabled="busy || !grantDraft.roleId || !grantDraft.eventId">
          {{ t("organizationAccess.saveGrant") }}
        </button>
        <button class="button button-secondary" type="button" :disabled="busy" @click="grantMember = null">{{ t("common.cancel") }}</button>
      </form>
      <h4>{{ t("organizationAccess.roles") }}</h4>
      <button v-if="eventPermissions.length" class="button button-secondary" type="button" :aria-expanded="showRoleForm"
        :disabled="busy" @click="showRoleForm = !showRoleForm">{{ t("organizationAccess.createRole") }}</button>
      <form v-if="showRoleForm" class="event-role-form" @submit.prevent="createRole">
        <label>{{ t("organizationAccess.roleCode") }}
          <input v-model="roleDraft.code" required maxlength="40" pattern="[A-Za-z0-9][A-Za-z0-9_\-]{0,39}">
        </label>
        <label>{{ t("organizationAccess.roleName") }}<input v-model="roleDraft.name" required maxlength="120"></label>
        <label>{{ t("organizationAccess.roleDescription") }}<input v-model="roleDraft.description" maxlength="500"></label>
        <fieldset>
          <legend>{{ t("organizationAccess.eventPermissions") }}</legend>
          <label>{{ t("organizationAccess.searchPermissions") }}<input v-model="permissionFilter" type="search"></label>
          <p aria-live="polite">{{ t("organizationAccess.selectedCount", { count: roleDraft.permissionCodes.length }) }}</p>
          <div class="event-role-permissions">
            <label v-for="permission in filteredEventPermissions" :key="permission.code">
              <input v-model="roleDraft.permissionCodes" type="checkbox" :value="permission.code" :disabled="busy">
              {{ permission.description }} · <code>{{ permission.code }}</code>
            </label>
            <p v-if="!filteredEventPermissions.length">{{ t("organizationAccess.noMatches") }}</p>
          </div>
        </fieldset>
        <button class="button button-primary" type="submit" :disabled="busy || !roleDraft.name.trim() || !roleDraft.permissionCodes.length">
          {{ t("organizationAccess.saveRole") }}
        </button>
      </form>
      <p v-if="!roles.length">{{ t("organizationAccess.noRoles") }}</p>
      <details v-for="role in roles" :key="role.roleId">
        <summary>{{ role.name }} · {{ t(`organizationAccess.scopes.${role.scope}`) }}</summary>
        <p v-if="role.retiredAt">{{ t("organizationAccess.retired") }}</p>
        <p v-if="role.description">{{ role.description }}</p>
        <button v-if="role.scope === 'event' && !role.systemPreset && !role.retiredAt" type="button"
          class="button button-secondary" :disabled="busy" @click="retireRole(role)">{{ t("organizationAccess.retireRole") }}</button>
        <p v-if="!role.permissionCodes.length">{{ t("organizationAccess.noPermissions") }}</p>
        <ul v-else>
          <li v-for="code in role.permissionCodes" :key="code">
            <code>{{ code }}</code><template v-if="permissionByCode.has(code)"> · {{ permissionByCode.get(code)?.description }}</template>
          </li>
        </ul>
      </details>
    </template>
  </section>
</template>

<style scoped>
.organization-access { margin-block-start: 1rem; }
.access-pagination { display: flex; flex-wrap: wrap; gap: 0.75rem; }
summary { cursor: pointer; }
.event-role-form { display: grid; gap: 0.75rem; margin-block: 0.75rem; }
.event-role-permissions { max-block-size: 16rem; overflow: auto; }
.event-role-permissions label { display: block; padding-block: 0.25rem; }
.event-role-permissions input { inline-size: auto; }
</style>
