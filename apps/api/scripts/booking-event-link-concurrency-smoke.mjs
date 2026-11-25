import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import pg from 'pg';
import {buildApi} from '../dist/src/server.js';
assert.ok(process.env.MIGRATOR_URL&&(process.env.DATABASE_URL_RUNTIME||process.env.RUNTIME_URL),'Set synthetic acceptance database role URLs');
const org='10000000-0000-0000-0000-00000000000a',booking='f0000000-0000-0000-0000-00000000000a';
const actor=randomUUID(),user=randomUUID(),role=randomUUID(),event=randomUUID();
let api,runtimePool;
const owner=new pg.Client({connectionString:process.env.MIGRATOR_URL});const clients=[];
try{
 await owner.connect();await owner.query('SET ROLE eventor_owner');await owner.query('BEGIN');await owner.query("SELECT set_config('app.organization_id',$1,true),set_config('app.actor_membership_id',$2,true)",[org,actor]);
 await owner.query("INSERT INTO eogp.users(id,email,display_name,status) VALUES($1,$2,'Synthetic booking link race operator','active')",[user,`booking-link-race-${user}@example.invalid`]);
 await owner.query("INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES($1,$2,$3,'active')",[actor,org,user]);
 await owner.query("INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES($1,$2,$3,'Synthetic booking link race role','organization')",[role,org,`CI-LINK-RACE-${role}`]);
 await owner.query("INSERT INTO eogp.role_permissions SELECT $1,$2,code FROM unnest(ARRAY['event.manage','booking.manage']) code",[org,role]);
 await owner.query("INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES($1,$2,$3,'organization',$2)",[org,actor,role]);
 await owner.query("INSERT INTO eogp.events(id,organization_id,event_code,title,created_by_membership_id) VALUES($1,$2,$3,'Synthetic duplicate association race',$4)",[event,org,`CI-LINK-${event}`,actor]);await owner.query('COMMIT');
 const connect=async()=>{const c=new pg.Client({connectionString:process.env.DATABASE_URL_RUNTIME??process.env.RUNTIME_URL});await c.connect();clients.push(c);await c.query("SET statement_timeout='10s'");await c.query('BEGIN');await c.query("SELECT set_config('app.organization_id',$1,true),set_config('app.actor_membership_id',$2,true)",[org,actor]);return c;};
 const first=await connect(),second=await connect(),observer=await connect();
 const sql="SELECT eogp.create_event_booking_link($1,$2,$3,$1,$4,NULL,'venue_for_event') AS data",args=[org,event,actor,booking];
 const created=(await first.query(sql,args)).rows[0].data;
 const pending=second.query(sql,args).then(result=>({result}),error=>({error}));
 let waited=false;
 try{
  for(let n=0;n<100;n++){
   const {rows}=await observer.query('SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1',[second.processID]);
   if(rows[0]?.wait_event_type==='Lock'){waited=true;break;}
   await new Promise(resolve=>setTimeout(resolve,25));
  }
  assert.ok(waited,'duplicate association did not serialize before the audited insert');
 }finally{await first.query('COMMIT');}
 const completed=await pending;assert.equal(completed.error,undefined);assert.equal(completed.result.rows[0].data.linkId,created.linkId);await second.query('COMMIT');
 await owner.query('BEGIN');await owner.query("SELECT set_config('app.organization_id',$1,true)",[org]);
 assert.equal((await owner.query('SELECT count(*)::integer AS count FROM eogp.booking_event_links WHERE organization_id=$1 AND event_id=$2',[org,event])).rows[0].count,1);
 assert.equal((await owner.query("SELECT count(*)::integer AS count FROM eogp.audit_events WHERE organization_id=$1 AND aggregate_id=$2 AND action='booking.event.linked'",[org,created.linkId])).rows[0].count,1);await owner.query('ROLLBACK');
 runtimePool=new pg.Pool({connectionString:process.env.DATABASE_URL_RUNTIME??process.env.RUNTIME_URL});
 api=buildApi({pool:runtimePool,authenticateStaff:async()=>({organizationId:org,membershipId:actor,userId:user}),verifyMutationOrigin:async()=>true});
 const request={method:'POST',url:`/events/${event}/booking-links`,headers:{'idempotency-key':`synthetic-link-api-${event}`},payload:{bookingOwnerOrganizationId:org,bookingId:booking,relationshipKind:'venue_for_event'}};
 const response=await api.inject(request);assert.equal(response.statusCode,201,response.body);assert.equal(response.json().data.linkId,created.linkId);
 assert.equal((await api.inject(request)).statusCode,201);
 await owner.query('BEGIN');await owner.query("SELECT set_config('app.organization_id',$1,true)",[org]);
 await owner.query("DELETE FROM eogp.role_permissions WHERE organization_id=$1 AND role_id=$2 AND permission_code='booking.manage'",[org,role]);await owner.query('COMMIT');
 const denied=await api.inject(request);assert.equal(denied.statusCode,403,denied.body);assert.equal(denied.json().code,'FORBIDDEN');
 const history=await api.inject({method:'GET',url:`/events/${event}/booking-links`});assert.equal(history.statusCode,200,history.body);assert.equal(history.json().data.links.length,1);
 console.log('PASS concurrent association requests create one link/audit; real PostgreSQL API retries recheck revoked booking authority');
}finally{if(api)await api.close();if(runtimePool)await runtimePool.end();await Promise.allSettled(clients.map(async c=>{await c.query('ROLLBACK');await c.end();}));await owner.end();}
