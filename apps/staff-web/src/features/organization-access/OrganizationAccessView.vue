<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
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
    if (failure instanceof ApiError && [401, 403].includes(failure.status)) {
      members.value = [];
      roles.value = [];
      permissions.value = [];
      loaded.value = false;
    }
    error.value = failure instanceof ApiError ? formatApiError(failure, t) : t("organizationAccess.failed");
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
              <td>{{ t(`organizationAccess.statuses.${member.status}`) }}</td>
              <td>
                <span v-if="!member.grants.length">{{ t("organizationAccess.noGrants") }}</span>
                <ul v-else>
                  <li v-for="grant in member.grants" :key="grant.grantId">
                    {{ grant.roleName }} · {{ describeScope(grant) }}
                    <small v-if="grant.expiresAt"> · {{ expiry(grant.expiresAt) }}</small>
                  </li>
                </ul>
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
      <h4>{{ t("organizationAccess.roles") }}</h4>
      <p v-if="!roles.length">{{ t("organizationAccess.noRoles") }}</p>
      <details v-for="role in roles" :key="role.roleId">
        <summary>{{ role.name }} · {{ t(`organizationAccess.scopes.${role.scope}`) }}</summary>
        <p v-if="role.description">{{ role.description }}</p>
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
</style>
