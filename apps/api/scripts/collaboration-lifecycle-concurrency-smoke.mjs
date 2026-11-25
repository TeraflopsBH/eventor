import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import pg from 'pg';
import {buildApi} from '../dist/src/server.js';
assert.ok(process.env.MIGRATOR_URL&&(process.env.DATABASE_URL_RUNTIME||process.env.RUNTIME_URL),'Set synthetic acceptance database role URLs');
const a='10000000-0000-0000-0000-00000000000a',b='10000000-0000-0000-0000-00000000000b',booking='f0000000-0000-0000-0000-00000000000a';
const user=randomUUID(),actorA=randomUUID(),actorB=randomUUID(),roleA=randomUUID(),roleB=randomUUID(),grants=[];
const owner=new pg.Client({connectionString:process.env.MIGRATOR_URL});const clients=[];let api,pool;
try{
 await owner.connect();await owner.query('SET ROLE eventor_owner');
 const ownerTransaction=async(org,actor,operation)=>{await owner.query('BEGIN');try{await owner.query("SELECT set_config('app.organization_id',$1,true),set_config('app.actor_membership_id',$2,true)",[org,actor]);const result=await operation();await owner.query('COMMIT');return result;}catch(error){await owner.query('ROLLBACK');throw error;}};
 await owner.query("INSERT INTO eogp.users(id,email,display_name,status) VALUES($1,$2,'Synthetic collaboration race manager','active')",[user,`collaboration-race-${user}@example.invalid`]);
 for(const [org,actor,role] of [[a,actorA,roleA],[b,actorB,roleB]])await ownerTransaction(org,actor,async()=>{
  await owner.query("INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES($1,$2,$3,'active')",[actor,org,user]);
  await owner.query("INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES($1,$2,$3,'Synthetic collaboration race role','organization')",[role,org,`CI-COLLAB-RACE-${role}`]);
  await owner.query("INSERT INTO eogp.role_permissions VALUES($1,$2,'collaboration.manage')",[org,role]);
  await owner.query("INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES($1,$2,$3,'organization',$2)",[org,actor,role]);
 });
 await ownerTransaction(a,actorA,async()=>{for(let n=0;n<3;n++)grants.push((await owner.query("SELECT eogp.propose_collaboration_grant(NULL,$1,'booking',NULL,NULL,$2,'Synthetic explicit booking collaboration',$3::jsonb,ARRAY['booking.event.link'],clock_timestamp()-interval '1 hour',clock_timestamp()+interval '1 day',$4) AS id",[b,booking,{reviewLabel:'Synthetic shared scope configuration'},actorA])).rows[0].id);});
 const connect=async()=>{const client=new pg.Client({connectionString:process.env.DATABASE_URL_RUNTIME??process.env.RUNTIME_URL});await client.connect();clients.push(client);await client.query("SET statement_timeout='10s'");return client;};
 const first=await connect(),second=await connect(),observer=await connect();
 const command='SELECT eogp.staff_collaboration_grant_action($1,$2,$3,$4,$5) AS data';
 for(let n=0;n<2;n++){
  const accept=[b,actorB,grants[n],'accept',null],revoke=[a,actorA,grants[n],'revoke','Synthetic grantor revocation'];
  const before=n===0?accept:revoke,after=n===0?revoke:accept;
  for(const [client,args] of [[first,before],[second,after]]){await client.query('BEGIN');await client.query("SELECT set_config('app.organization_id',$1,true),set_config('app.actor_membership_id',$2,true)",args.slice(0,2));}
  const original=(await first.query(command,before)).rows[0].data;
  const pending=second.query(command,after).then(result=>({result}),error=>({error}));let waited=false;
  try{for(let attempt=0;attempt<100;attempt++){
   const {rows}=await observer.query('SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1',[second.processID]);if(rows[0]?.wait_event_type==='Lock'){waited=true;break;}await new Promise(resolve=>setTimeout(resolve,25));
  }assert.ok(waited,'acceptance/revocation did not serialize on the shared grant');}finally{await first.query('COMMIT');}
  const completed=await pending;
  if(n===0){assert.equal(completed.error,undefined);assert.equal(completed.result.rows[0].data.acceptedAt,original.acceptedAt);assert.equal(completed.result.rows[0].data.status,'revoked');await second.query('COMMIT');}
  else{assert.equal(completed.error?.code,'55000','revoked proposal was accepted');await second.query('ROLLBACK');}
  await ownerTransaction(a,actorA,async()=>{
   const row=(await owner.query('SELECT status,accepted_by_membership_id FROM eogp.collaboration_grants WHERE organization_id=$1 AND id=$2',[a,grants[n]])).rows[0];assert.equal(row.status,'revoked');assert.equal(row.accepted_by_membership_id,n===0?actorB:null);
   assert.equal((await owner.query("SELECT count(*)::integer AS count FROM eogp.audit_events WHERE organization_id=$1 AND aggregate_id=$2 AND action='collaboration.grant.revoked'",[a,grants[n]])).rows[0].count,1);
  });
  await ownerTransaction(b,actorB,async()=>{assert.equal((await owner.query("SELECT count(*)::integer AS count FROM eogp.audit_events WHERE organization_id=$1 AND aggregate_id=$2 AND action='collaboration.grant.accepted'",[b,grants[n]])).rows[0].count,n===0?1:0);});
 }
 pool=new pg.Pool({connectionString:process.env.DATABASE_URL_RUNTIME??process.env.RUNTIME_URL});let principal={organizationId:b,membershipId:actorB,userId:user};api=buildApi({pool,authenticateStaff:async()=>principal,verifyMutationOrigin:async()=>true});
 const accept={method:'POST',url:`/collaboration-grants/${grants[2].toUpperCase()}/accept`,headers:{'idempotency-key':`accept-collaboration-${grants[2]}`},payload:{}};
 const accepted=await api.inject(accept);assert.equal(accepted.statusCode,200,accepted.body);assert.equal((await api.inject({...accept,url:accept.url.toLowerCase()})).statusCode,200);
 const list=await api.inject({method:'GET',url:`/organizations/${b}/collaboration-grants`});assert.equal(list.statusCode,200,list.body);assert.ok(list.json().data.grants.every(grant=>!Object.hasOwn(grant,'projection')));
 const detail=await api.inject({method:'GET',url:`/collaboration-grants/${grants[2]}`});assert.equal(detail.statusCode,200,detail.body);assert.equal(detail.json().data.projection.reviewLabel,'Synthetic shared scope configuration');
 principal={organizationId:a,membershipId:actorA,userId:user};
 const revoke={method:'POST',url:`/collaboration-grants/${grants[2]}/revoke`,headers:{'idempotency-key':`revoke-collaboration-${grants[2]}`},payload:{reason:' Synthetic grantor revocation '}};
 const revoked=await api.inject(revoke);assert.equal(revoked.statusCode,200,revoked.body);assert.equal(revoked.json().data.acceptedAt,accepted.json().data.acceptedAt);
 const repeated=await api.inject({...revoke,payload:{reason:revoke.payload.reason.trim()}});assert.equal(repeated.statusCode,200,repeated.body);assert.equal(repeated.json().data.revokedAt,revoked.json().data.revokedAt);
 principal={organizationId:b,membershipId:actorB,userId:user};assert.equal((await api.inject(accept)).statusCode,409,'cached acceptance ignored source revocation');
 const reviewedGrant=await ownerTransaction(a,actorA,async()=>(await owner.query("SELECT eogp.propose_collaboration_grant(NULL,$1,'booking',NULL,NULL,$2,'Synthetic reviewed booking collaboration','{}',ARRAY['booking.event.link'],clock_timestamp()-interval '1 hour',clock_timestamp()+interval '1 day',$3) AS id",[b,booking,actorA])).rows[0].id);
 const reviewedDetails=await api.inject({method:'GET',url:`/collaboration-grants/${reviewedGrant}`});assert.equal(reviewedDetails.statusCode,200,reviewedDetails.body);const oldFingerprint=reviewedDetails.json().data.reviewFingerprint;assert.match(oldFingerprint,/^[a-f0-9]{64}$/);
 await ownerTransaction(a,actorA,()=>owner.query("UPDATE eogp.collaboration_grants SET projection=$3::jsonb WHERE organization_id=$1 AND id=$2",[a,reviewedGrant,{reviewLabel:'Synthetic privileged source correction'}]));
 const reviewedRequest={method:'POST',url:`/collaboration-grants/${reviewedGrant}/accept`,headers:{'idempotency-key':`reviewed-collaboration-${reviewedGrant}`},payload:{expectedReviewFingerprint:oldFingerprint}};
 assert.equal((await api.inject(reviewedRequest)).statusCode,409,'stale reviewed scope was accepted');
 const refreshed=await api.inject({method:'GET',url:`/collaboration-grants/${reviewedGrant}`});assert.equal(refreshed.json().data.status,'proposed');const freshFingerprint=refreshed.json().data.reviewFingerprint;assert.notEqual(freshFingerprint,oldFingerprint);
 const pinnedRequest={...reviewedRequest,payload:{expectedReviewFingerprint:freshFingerprint}};
 const pinned=await api.inject(pinnedRequest);assert.equal(pinned.statusCode,200,pinned.body);assert.equal((await api.inject(pinnedRequest)).statusCode,200);
 await ownerTransaction(a,actorA,()=>owner.query("UPDATE eogp.collaboration_grants SET projection=$3::jsonb WHERE organization_id=$1 AND id=$2",[a,reviewedGrant,{reviewLabel:'Synthetic later privileged correction'}]));
 assert.equal((await api.inject(pinnedRequest)).statusCode,409,'cached interactive acceptance ignored changed reviewed meaning');
 await ownerTransaction(b,actorB,()=>owner.query("DELETE FROM eogp.role_permissions WHERE organization_id=$1 AND role_id=$2 AND permission_code='collaboration.manage'",[b,roleB]));
 assert.equal((await api.inject(accept)).statusCode,403,'cached acceptance ignored role revocation');
 assert.equal((await api.inject(pinnedRequest)).statusCode,403,'cached reviewed acceptance ignored role revocation');
 principal={organizationId:a,membershipId:actorA,userId:user};await ownerTransaction(a,actorA,()=>owner.query("DELETE FROM eogp.role_permissions WHERE organization_id=$1 AND role_id=$2 AND permission_code='collaboration.manage'",[a,roleA]));
 assert.equal((await api.inject(revoke)).statusCode,403,'cached revocation ignored role revocation');
 console.log('PASS acceptance/revocation serialize in both orders and preserve authentic history/audits; real PostgreSQL API reviewed acceptance and cached retries enforce changed scope and grant/role revocation');
}finally{if(api)await api.close();if(pool)await pool.end();await Promise.allSettled(clients.map(async client=>{await client.query('ROLLBACK');await client.end();}));await owner.end();}
