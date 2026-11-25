import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import pg from 'pg';
import {buildApi} from '../dist/src/server.js';
assert.ok(process.env.MIGRATOR_URL&&(process.env.DATABASE_URL_RUNTIME||process.env.RUNTIME_URL),'Set synthetic acceptance database role URLs');
const org='10000000-0000-0000-0000-00000000000a',booking='f0000000-0000-0000-0000-00000000000a';
const actor=randomUUID(),user=randomUUID(),role=randomUUID(),event=randomUUID(),source=randomUUID();
const owner=new pg.Client({connectionString:process.env.MIGRATOR_URL});const clients=[];let api,pool;
try{
 await owner.connect();await owner.query('SET ROLE eventor_owner');
 const ownerTransaction=async operation=>{await owner.query('BEGIN');try{await owner.query("SELECT set_config('app.organization_id',$1,true),set_config('app.actor_membership_id',$2,true)",[org,actor]);const result=await operation();await owner.query('COMMIT');return result;}catch(error){await owner.query('ROLLBACK');throw error;}};
 await ownerTransaction(async()=>{
  await owner.query("INSERT INTO eogp.users(id,email,display_name,status) VALUES($1,$2,'Synthetic notice race operator','active')",[user,`notice-race-${user}@example.invalid`]);
  await owner.query("INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES($1,$2,$3,'active')",[actor,org,user]);
  await owner.query("INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES($1,$2,$3,'Synthetic notice race role','organization')",[role,org,`CI-NOTICE-RACE-${role}`]);
  await owner.query("INSERT INTO eogp.role_permissions SELECT $1,$2,code FROM unnest(ARRAY['event.manage','booking.manage']) code",[org,role]);
  await owner.query("INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES($1,$2,$3,'organization',$2)",[org,actor,role]);
  await owner.query("INSERT INTO eogp.events(id,organization_id,event_code,title,created_by_membership_id) VALUES($1,$2,$3,'Synthetic duplicate notice race',$4)",[event,org,`CI-NOTICE-${event}`,actor]);
  await owner.query("SELECT eogp.create_event_booking_link($1,$2,$3,$1,$4,NULL,'venue_for_event')",[org,event,actor,booking]);
  await owner.query("SELECT eogp.record_booking_disruption_notice($1,$2,$3,$4,'synthetic_disruption','Synthetic public notice',NULL,NULL)",[org,booking,actor,source]);
 });
 const connect=async()=>{const client=new pg.Client({connectionString:process.env.DATABASE_URL_RUNTIME??process.env.RUNTIME_URL});await client.connect();clients.push(client);await client.query("SET statement_timeout='10s'");return client;};
 const first=await connect(),second=await connect(),observer=await connect();
 const race=async(sql,args)=>{
  for(const client of [first,second]){await client.query('BEGIN');await client.query("SELECT set_config('app.organization_id',$1,true),set_config('app.actor_membership_id',$2,true)",[org,actor]);}
  const original=(await first.query(sql,args)).rows[0].data;
  const pending=second.query(sql,args).then(result=>({result}),error=>({error}));let waited=false;
  try{for(let n=0;n<100;n++){
   const {rows}=await observer.query('SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1',[second.processID]);
   if(rows[0]?.wait_event_type==='Lock'){waited=true;break;}await new Promise(resolve=>setTimeout(resolve,25));
  }assert.ok(waited,'duplicate notice command did not serialize');}finally{await first.query('COMMIT');}
  const completed=await pending;assert.equal(completed.error,undefined);assert.deepEqual(completed.result.rows[0].data,original);await second.query('COMMIT');return original;
 };
 const published=await race('SELECT eogp.publish_local_event_disruption($1,$2,$3,$4,$5) AS data',[org,event,actor,booking,source]);
 const receipt=published.noticeId;const acknowledged=await race('SELECT eogp.acknowledge_event_disruption($1,$2,$3) AS data',[org,receipt,actor]);assert.equal(acknowledged.status,'acknowledged');assert.ok(acknowledged.acknowledgedAt);
 await ownerTransaction(async()=>{
  assert.equal((await owner.query('SELECT count(*)::integer AS count FROM eogp.event_disruption_resolutions WHERE organization_id=$1 AND event_id=$2',[org,event])).rows[0].count,1);
  for(const action of ['event.disruption_notice.published','event.disruption_notice.acknowledged'])assert.equal((await owner.query('SELECT count(*)::integer AS count FROM eogp.audit_events WHERE organization_id=$1 AND aggregate_id=$2 AND action=$3',[org,receipt,action])).rows[0].count,1);
 });
 pool=new pg.Pool({connectionString:process.env.DATABASE_URL_RUNTIME??process.env.RUNTIME_URL});
 api=buildApi({pool,authenticateStaff:async()=>({organizationId:org,membershipId:actor,userId:user}),verifyMutationOrigin:async()=>true});
 const publication={method:'POST',url:`/events/${event}/disruption-notices`,headers:{'idempotency-key':`notice-publish-${event}`},payload:{bookingId:booking,sourceBookingNoticeId:source}};
 const ack={method:'POST',url:`/event-disruption-notices/${receipt}/acknowledge`,headers:{'idempotency-key':`notice-ack-${receipt}`},payload:{}};
 for(let retry=0;retry<2;retry++){const result=await api.inject(publication);assert.equal(result.statusCode,201,result.body);assert.equal(result.json().data.noticeId,receipt);const resultAck=await api.inject(ack);assert.equal(resultAck.statusCode,200,resultAck.body);assert.equal(resultAck.json().data.acknowledgedAt,acknowledged.acknowledgedAt);}
 assert.equal((await api.inject({...ack,url:`/event-disruption-notices/${source}/acknowledge`,headers:{'idempotency-key':`wrong-source-${source}`}})).statusCode,404,'source ID was treated as receipt identity');
 await ownerTransaction(()=>owner.query("DELETE FROM eogp.role_permissions WHERE organization_id=$1 AND role_id=$2 AND permission_code='booking.manage'",[org,role]));
 assert.equal((await api.inject(publication)).statusCode,403,'cached publication ignored revoked source authority');
 assert.equal((await api.inject(ack)).statusCode,200,'event-only acknowledgement lost deliberate receipt access');
 await ownerTransaction(()=>owner.query("DELETE FROM eogp.role_permissions WHERE organization_id=$1 AND role_id=$2 AND permission_code='event.manage'",[org,role]));
 assert.equal((await api.inject(ack)).statusCode,403,'cached acknowledgement ignored revoked event scope');
 assert.equal((await api.inject({method:'GET',url:`/events/${event}/disruption-notices`})).statusCode,403);
 console.log('PASS concurrent notice publication/acknowledgement retain one receipt, audit and original timestamp; real PostgreSQL API retries enforce source/event revocation and receipt identity');
}finally{if(api)await api.close();if(pool)await pool.end();await Promise.allSettled(clients.map(async client=>{await client.query('ROLLBACK');await client.end();}));await owner.end();}
