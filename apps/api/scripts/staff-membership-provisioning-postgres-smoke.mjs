import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import pg from 'pg';
import {bootstrapStaffAccount} from '../dist/src/staff-account-bootstrap.js';
import {provisionStaffMembership} from '../dist/src/staff-membership-provisioning.js';
import {PostgresStaffSessionAuth} from '../dist/src/session-auth.js';
assert.ok(process.env.MIGRATOR_URL && process.env.AUTH_URL && (process.env.DATABASE_URL_RUNTIME || process.env.RUNTIME_URL),'Set synthetic acceptance database role URLs');
const pool=new pg.Pool({connectionString:process.env.MIGRATOR_URL});
const runtime=new pg.Pool({connectionString:process.env.DATABASE_URL_RUNTIME??process.env.RUNTIME_URL});
const auth=new pg.Pool({connectionString:process.env.AUTH_URL});
const first='10000000-0000-0000-0000-00000000000a',second='10000000-0000-0000-0000-00000000000b';
const email=`membership-${randomUUID()}@example.invalid`,password='Synthetic-membership-only-2026';
const inspect=async(org,sql,values=[],commit=false)=>{
 const client=await pool.connect();try{
  await client.query('BEGIN');await client.query('SET LOCAL ROLE eventor_owner');await client.query("SELECT set_config('app.organization_id',$1,true)",[org]);
  const result=await client.query(sql,values);await client.query(commit?'COMMIT':'ROLLBACK');return result.rows;
 }catch(e){await client.query('ROLLBACK');throw e;}finally{client.release();}
};
const input={email,organizationId:second,reason:'synthetic existing-account workspace acceptance'};
const script=fileURLToPath(new URL('../../../scripts/admin/provision-staff-membership.sh',import.meta.url));
try{
 const created=await bootstrapStaffAccount(pool,{email,password,displayName:'Synthetic existing account',organizationId:first,reason:'synthetic membership prerequisite'});
 const sessions=new PostgresStaffSessionAuth(auth,{allowedOrigins:['https://staff.example.test'],fingerprintKey:Buffer.alloc(32,8)});
 const request={headers:{origin:'https://staff.example.test'},ip:'198.51.100.72'};
 const oldSession=await sessions.createStaffSession(request,{email,password});assert.equal(oldSession.principal.organizationId,first);
 const [before]=await inspect(first,'SELECT to_jsonb(account) AS data FROM eogp.users account WHERE id=$1',[created.userId]);
 const [originalMember]=await inspect(first,'SELECT to_jsonb(member) AS data FROM eogp.organization_memberships member WHERE id=$1',[created.membershipId]);
 const added=await provisionStaffMembership(pool,{...input,email:email.toUpperCase()});assert.equal(added.userId,created.userId);
 assert.deepEqual((await inspect(first,'SELECT to_jsonb(account) AS data FROM eogp.users account WHERE id=$1',[created.userId]))[0],before);
 assert.deepEqual((await inspect(first,'SELECT to_jsonb(member) AS data FROM eogp.organization_memberships member WHERE id=$1',[created.membershipId]))[0],originalMember);
 assert.equal((await inspect(first,'SELECT revoked_at FROM eogp.user_sessions WHERE id=$1',[oldSession.principal.sessionId]))[0].revoked_at,null);
 assert.equal((await inspect(second,'SELECT id FROM eogp.user_role_grants WHERE membership_id=$1',[added.membershipId])).length,0);
 const [audit]=await inspect(second,"SELECT database_principal,reason FROM eogp.platform_admin_audit WHERE user_id=$1 AND organization_id=$2 AND action='staff_membership_provisioned'",[created.userId,second]);
 assert.equal(audit.database_principal,(await inspect(second,'SELECT session_user AS name'))[0].name);assert.equal(audit.reason,input.reason);
 const choices=await sessions.createStaffSession(request,{email,password});assert.equal(choices.organizationSelectionRequired,true);assert.deepEqual(choices.organizations.map(o=>o.organizationId).sort(),[first,second].sort());
 const selected=await sessions.createStaffSession(request,{email,password,organizationId:second});assert.equal(selected.principal.membershipId,added.membershipId);
 const client=await runtime.connect();try{
  await client.query('BEGIN');await client.query("SELECT set_config('app.organization_id',$1,true),set_config('app.actor_membership_id',$2,true)",[second,added.membershipId]);
  await assert.rejects(client.query('SELECT eogp.assert_guest_registry_permission($1,$2,false)',[second,added.membershipId]),e=>e.code==='42501');
 }finally{await client.query('ROLLBACK');client.release();}
 // Every existing membership state is refused without restoring or mutating it.
 for(const status of ['active','invited','suspended','revoked']){
  await inspect(second,"UPDATE eogp.organization_memberships SET status=$2,revoked_at=CASE WHEN $2='revoked' THEN clock_timestamp() ELSE NULL END WHERE id=$1",[added.membershipId,status],true);
  const [member]=await inspect(second,'SELECT to_jsonb(member) AS data FROM eogp.organization_memberships member WHERE id=$1',[added.membershipId]);
  await assert.rejects(provisionStaffMembership(pool,input),e=>e.code==='MEMBERSHIP_EXISTS');
  assert.deepEqual((await inspect(second,'SELECT to_jsonb(member) AS data FROM eogp.organization_memberships member WHERE id=$1',[added.membershipId]))[0],member);
 }
 await assert.rejects(provisionStaffMembership(pool,{...input,email:`missing-${randomUUID()}@example.invalid`}),e=>e.code==='ACCOUNT_UNAVAILABLE');
 await assert.rejects(provisionStaffMembership(pool,{...input,organizationId:randomUUID()}),e=>e.code==='ORGANIZATION_UNAVAILABLE');
 await assert.rejects(provisionStaffMembership(runtime,input),e=>e.code==='OWNER_REQUIRED');
 const unassigned=await bootstrapStaffAccount(pool,{email:`membership-race-${randomUUID()}@example.invalid`,password,displayName:'Synthetic membership race',reason:'synthetic membership race prerequisite'});
 const [raceAccount]=await inspect(first,'SELECT email FROM eogp.users WHERE id=$1',[unassigned.userId]);
 const racing=await Promise.allSettled([provisionStaffMembership(pool,{...input,email:raceAccount.email}),provisionStaffMembership(pool,{...input,email:raceAccount.email})]);
 assert.equal(racing.filter(r=>r.status==='fulfilled').length,1);assert.equal(racing.find(r=>r.status==='rejected').reason.code,'MEMBERSHIP_EXISTS');
 assert.equal((await inspect(second,"SELECT id FROM eogp.platform_admin_audit WHERE user_id=$1 AND action='staff_membership_provisioned'",[unassigned.userId])).length,1);
 // Non-active accounts and organizations are never implicitly reactivated.
 const disabled=await bootstrapStaffAccount(pool,{email:`membership-disabled-${randomUUID()}@example.invalid`,password,displayName:'Synthetic disabled account',reason:'synthetic refusal prerequisite'});
 await inspect(first,"UPDATE eogp.users SET status='disabled' WHERE id=$1",[disabled.userId],true);
 const disabledEmail=(await inspect(first,'SELECT email FROM eogp.users WHERE id=$1',[disabled.userId]))[0].email;
 await assert.rejects(provisionStaffMembership(pool,{...input,email:disabledEmail}),e=>e.code==='ACCOUNT_UNAVAILABLE');
 const inactive=randomUUID();await inspect(inactive,"INSERT INTO eogp.organizations(id,slug,name,status) VALUES($1,$2,'Synthetic inactive organization','suspended')",[inactive,`membership-inactive-${inactive}`],true);
 await assert.rejects(provisionStaffMembership(pool,{...input,organizationId:inactive}),e=>e.code==='ORGANIZATION_UNAVAILABLE');
 const cliAccount=await bootstrapStaffAccount(pool,{email:`membership-cli-${randomUUID()}@example.invalid`,password,displayName:'Synthetic membership CLI',reason:'synthetic CLI prerequisite'});
 const cliEmail=(await inspect(first,'SELECT email FROM eogp.users WHERE id=$1',[cliAccount.userId]))[0].email;
 const cli=spawnSync('bash',[script,'--email',cliEmail,'--organization',second,'--reason','synthetic CLI acceptance'],{env:process.env,encoding:'utf8'});
 assert.equal(cli.status,0,cli.stderr);assert.equal(JSON.parse(cli.stdout).accountChanged,false);assert.equal(JSON.parse(cli.stdout).rolesGranted,false);
 const refused=spawnSync('bash',[script,'--email',cliEmail,'--organization',second,'--reason','synthetic duplicate CLI refusal'],{env:process.env,encoding:'utf8'});
 assert.equal(refused.status,1);assert.ok(!refused.stderr.includes('postgresql://') && !refused.stderr.includes(password));
 console.log('PASS host existing-account membership: named workspaces, unchanged account/session/other membership, no implicit grants, audit, concurrent duplicate, inactive/existing refusal, runtime denial and CLI');
}finally{await Promise.all([pool.end(),runtime.end(),auth.end()]);}
