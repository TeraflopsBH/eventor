import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import pg from 'pg';
import {buildApi} from '../dist/src/server.js';
assert.ok(process.env.MIGRATOR_URL&&(process.env.DATABASE_URL_RUNTIME||process.env.RUNTIME_URL),'Set synthetic acceptance database role URLs');
const org='10000000-0000-0000-0000-00000000000a',booking='f0000000-0000-0000-0000-00000000000a';
const actor=randomUUID(),user=randomUUID(),role=randomUUID(),events=[randomUUID(),randomUUID(),randomUUID()],source=randomUUID(),links=[];
const owner=new pg.Client({connectionString:process.env.MIGRATOR_URL});const clients=[];let api,pool;
try{
 await owner.connect();await owner.query('SET ROLE eventor_owner');
 const ownerTransaction=async operation=>{await owner.query('BEGIN');try{await owner.query("SELECT set_config('app.organization_id',$1,true),set_config('app.actor_membership_id',$2,true)",[org,actor]);const result=await operation();await owner.query('COMMIT');return result;}catch(error){await owner.query('ROLLBACK');throw error;}};
 await ownerTransaction(async()=>{
  await owner.query("INSERT INTO eogp.users(id,email,display_name,status) VALUES($1,$2,'Synthetic association ending race operator','active')",[user,`end-link-race-${user}@example.invalid`]);
  await owner.query("INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES($1,$2,$3,'active')",[actor,org,user]);
  await owner.query("INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES($1,$2,$3,'Synthetic association ending race role','organization')",[role,org,`CI-END-LINK-${role}`]);
  await owner.query("INSERT INTO eogp.role_permissions SELECT $1,$2,code FROM unnest(ARRAY['event.manage','booking.manage']) code",[org,role]);
  await owner.query("INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES($1,$2,$3,'organization',$2)",[org,actor,role]);
  for(const event of events){await owner.query("INSERT INTO eogp.events(id,organization_id,event_code,title,created_by_membership_id) VALUES($1,$2,$3,'Synthetic publication and ending race',$4)",[event,org,`CI-END-LINK-${event}`,actor]);links.push((await owner.query("SELECT eogp.create_event_booking_link($1,$2,$3,$1,$4,NULL,'venue_for_event') AS data",[org,event,actor,booking])).rows[0].data.linkId);}
  await owner.query("SELECT eogp.record_booking_disruption_notice($1,$2,$3,$4,'synthetic_disruption','Synthetic public ending race',NULL,NULL)",[org,booking,actor,source]);
 });
 const connect=async()=>{const client=new pg.Client({connectionString:process.env.DATABASE_URL_RUNTIME??process.env.RUNTIME_URL});await client.connect();clients.push(client);await client.query("SET statement_timeout='10s'");return client;};
 const first=await connect(),second=await connect(),observer=await connect();
 for(const [index,event] of events.entries()){
  for(const client of [first,second]){await client.query('BEGIN');await client.query("SELECT set_config('app.organization_id',$1,true),set_config('app.actor_membership_id',$2,true)",[org,actor]);}
  const publish=['SELECT eogp.publish_local_event_disruption($1,$2,$3,$4,$5) AS data',[org,event,actor,booking,source]];
  const end=['SELECT eogp.end_event_booking_link($1,$2,$3,$4) AS data',[org,event,actor,links[index]]];
  const before=index===0?publish:end,after=index===1?publish:end;
  const original=(await first.query(...before)).rows[0].data;
  const pending=second.query(...after).then(result=>({result}),error=>({error}));let waited=false;
  try{for(let n=0;n<100;n++){
   const {rows}=await observer.query('SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1',[second.processID]);if(rows[0]?.wait_event_type==='Lock'){waited=true;break;}await new Promise(resolve=>setTimeout(resolve,25));
  }assert.ok(waited,'ending/publication commands failed to serialize');}finally{await first.query('COMMIT');}
  const completed=await pending;
  if(index!==1){assert.equal(completed.error,undefined);assert.equal(completed.result.rows[0].data.status,'ended');await second.query('COMMIT');}
  else{assert.equal(completed.error?.code,'55000','publication through an ended link succeeded');await second.query('ROLLBACK');}
  await ownerTransaction(async()=>{
   const rows=(await owner.query('SELECT id FROM eogp.event_disruption_resolutions WHERE organization_id=$1 AND event_id=$2',[org,event])).rows;
   assert.equal(rows.length,index===0?1:0);if(index===0)assert.equal(rows[0].id,original.noticeId);
   assert.equal((await owner.query("SELECT count(*)::integer AS count FROM eogp.audit_events WHERE organization_id=$1 AND aggregate_id=$2 AND action='booking.event.link.ended'",[org,links[index]])).rows[0].count,1);
  });
 }
 pool=new pg.Pool({connectionString:process.env.DATABASE_URL_RUNTIME??process.env.RUNTIME_URL});api=buildApi({pool,authenticateStaff:async()=>({organizationId:org,membershipId:actor,userId:user}),verifyMutationOrigin:async()=>true});
 const request={method:'POST',url:`/events/${events[0]}/booking-links/${links[0]}/end`,headers:{'idempotency-key':`end-link-api-${links[0]}`},payload:{}};
 for(let retry=0;retry<2;retry++){const result=await api.inject(request);assert.equal(result.statusCode,200,result.body);assert.equal(result.json().data.status,'ended');}
 await ownerTransaction(()=>owner.query("DELETE FROM eogp.role_permissions WHERE organization_id=$1 AND role_id=$2 AND permission_code='event.manage'",[org,role]));
 assert.equal((await api.inject(request)).statusCode,403,'cached ending ignored revoked event authority');
 console.log('PASS publication/ending serialize in both orders and duplicate endings retain prior receipts and one ending audit; real PostgreSQL API retries recheck revoked event authority');
}finally{if(api)await api.close();if(pool)await pool.end();await Promise.allSettled(clients.map(async client=>{await client.query('ROLLBACK');await client.end();}));await owner.end();}
