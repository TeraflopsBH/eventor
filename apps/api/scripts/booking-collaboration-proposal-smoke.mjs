import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import pg from 'pg';
import {buildApi} from '../dist/src/server.js';
const a='10000000-0000-0000-0000-00000000000a',b='10000000-0000-0000-0000-00000000000b',booking='f0000000-0000-0000-0000-00000000000a';
const user=randomUUID(),actorA=randomUUID(),actorB=randomUUID(),roleA=randomUUID(),roleB=randomUUID(),bookingRole=randomUUID(),event=randomUUID();
const owner=new pg.Client({connectionString:process.env.MIGRATOR_URL});let api,pool;
try{
 await owner.connect();await owner.query('SET ROLE eventor_owner');
 const transaction=async(org,actor,operation)=>{await owner.query('BEGIN');try{await owner.query("SELECT set_config('app.organization_id',$1,true),set_config('app.actor_membership_id',$2,true)",[org,actor]);const result=await operation();await owner.query('COMMIT');return result;}catch(error){await owner.query('ROLLBACK');throw error;}};
 await owner.query("INSERT INTO eogp.users(id,email,display_name,status) VALUES($1,$2,'Synthetic booking collaboration operator','active')",[user,`booking-proposal-api-${user}@example.invalid`]);
 for(const [org,actor,role] of [[a,actorA,roleA],[b,actorB,roleB]])await transaction(org,actor,async()=>{
  await owner.query("INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES($1,$2,$3,'active')",[actor,org,user]);
  await owner.query("INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES($1,$2,$3,'Synthetic proposal manager','organization')",[role,org,`CI-PROPOSE-API-${role}`]);
  await owner.query("INSERT INTO eogp.role_permissions VALUES($1,$2,'collaboration.manage')",[org,role]);
  await owner.query("INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES($1,$2,$3,'organization',$2)",[org,actor,role]);
 });
 const before=await transaction(a,actorA,async()=>{
  await owner.query("INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES($1,$2,$3,'Synthetic exact source booking manager','booking')",[bookingRole,a,`CI-PROPOSE-BOOK-${bookingRole}`]);
  await owner.query("INSERT INTO eogp.role_permissions VALUES($1,$2,'booking.manage')",[a,bookingRole]);
  await owner.query("INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,scope_booking_id,granted_by_membership_id) VALUES($1,$2,$3,'booking',$4,$2)",[a,actorA,bookingRole,booking]);
  return(await owner.query('SELECT to_jsonb(record) AS data FROM eogp.booking_records record WHERE organization_id=$1 AND id=$2',[a,booking])).rows[0].data;
 });
 await transaction(b,actorB,async()=>{
  await owner.query("INSERT INTO eogp.role_permissions VALUES($1,$2,'event.manage')",[b,roleB]);
  await owner.query("INSERT INTO eogp.events(id,organization_id,event_code,title,created_by_membership_id) VALUES($1,$2,$3,'Synthetic proposed collaboration event',$4)",[event,b,`CI-PROPOSE-${event}`,actorB]);
 });
 pool=new pg.Pool({connectionString:process.env.DATABASE_URL_RUNTIME??process.env.RUNTIME_URL});let principal={organizationId:a,membershipId:actorA,userId:user};api=buildApi({pool,authenticateStaff:async()=>principal,verifyMutationOrigin:async()=>true});
 const request={method:'POST',url:`/bookings/${booking}/collaboration-grants`,headers:{'idempotency-key':`booking-proposal-${event}`},payload:{granteeOrganizationId:b,purpose:'Synthetic narrow booking collaboration',validFrom:new Date(Date.now()-3600000).toISOString(),validUntil:null}};
 const [first,second]=await Promise.all([api.inject(request),api.inject(request)]);assert.equal(first.statusCode,201,first.body);assert.equal(second.statusCode,201,second.body);const proposal=first.json().data;assert.equal(second.json().data.grantId,proposal.grantId);assert.equal(proposal.status,'proposed');assert.deepEqual(proposal.allowedActions,['booking.event.link']);
 await transaction(a,actorA,async()=>{
  assert.equal((await owner.query('SELECT count(*)::integer AS count FROM eogp.collaboration_grant_revisions WHERE organization_id=$1 AND grant_id=$2',[a,proposal.grantId])).rows[0].count,1);
  assert.equal((await owner.query("SELECT count(*)::integer AS count FROM eogp.audit_events WHERE organization_id=$1 AND aggregate_id=$2 AND action='collaboration.grant.proposed'",[a,proposal.grantId])).rows[0].count,1);
  assert.deepEqual((await owner.query('SELECT to_jsonb(record) AS data FROM eogp.booking_records record WHERE organization_id=$1 AND id=$2',[a,booking])).rows[0].data,before);
 });
 principal={organizationId:b,membershipId:actorB,userId:user};const linking={method:'POST',url:`/events/${event}/booking-links`,headers:{'idempotency-key':`booking-proposal-link-${event}`},payload:{bookingOwnerOrganizationId:a,bookingId:booking,collaborationGrantId:proposal.grantId,relationshipKind:'venue_for_event'}};
 assert.equal((await api.inject(linking)).statusCode,403,'unaccepted proposal authorized linking');
 const review=await api.inject({method:'GET',url:`/collaboration-grants/${proposal.grantId}`});assert.equal(review.statusCode,200,review.body);
 const accepted=await api.inject({method:'POST',url:`/collaboration-grants/${proposal.grantId}/accept`,headers:{'idempotency-key':`booking-proposal-accept-${event}`},payload:{expectedReviewFingerprint:review.json().data.reviewFingerprint}});assert.equal(accepted.statusCode,200,accepted.body);assert.equal((await api.inject(linking)).statusCode,201);
 principal={organizationId:a,membershipId:actorA,userId:user};const receipt=await api.inject(request);assert.equal(receipt.statusCode,201);assert.equal(receipt.json().data.status,'proposed','creation retry changed its historical receipt');
 await transaction(a,actorA,()=>owner.query("UPDATE eogp.user_role_grants SET revoked_at=clock_timestamp() WHERE organization_id=$1 AND membership_id=$2 AND role_id=$3 AND revoked_at IS NULL",[a,actorA,bookingRole]));
 assert.equal((await api.inject(request)).statusCode,403,'cached proposal ignored revoked booking scope');
 await transaction(a,actorA,async()=>{
  await owner.query("INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,scope_booking_id,granted_by_membership_id) VALUES($1,$2,$3,'booking',$4,$2)",[a,actorA,bookingRole,booking]);
  await owner.query("DELETE FROM eogp.role_permissions WHERE organization_id=$1 AND role_id=$2 AND permission_code='collaboration.manage'",[a,roleA]);
 });
 assert.equal((await api.inject(request)).statusCode,403,'cached proposal ignored revoked collaboration authority');
 console.log('PASS concurrent API proposal retries create one grant/revision/audit; recipient review/acceptance is required, source facts stay unchanged and both revoked authorities deny cached replies');
}finally{if(api)await api.close();if(pool)await pool.end();await owner.end();}
