import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import pg from 'pg';
assert.ok(process.env.MIGRATOR_URL && process.env.DATABASE_URL_RUNTIME,'Set MIGRATOR_URL and DATABASE_URL_RUNTIME for the synthetic acceptance database');
const org='10000000-0000-0000-0000-00000000000a';
const actor=randomUUID(),user=randomUUID(),role=randomUUID();
const owner=new pg.Client({connectionString:process.env.MIGRATOR_URL});
const sessions=[];
try{
 await owner.connect();await owner.query('SET ROLE eventor_owner');await owner.query('BEGIN');
 await owner.query("SELECT set_config('app.organization_id',$1,true),set_config('app.actor_membership_id',$2,true)",[org,actor]);
 await owner.query("INSERT INTO eogp.users(id,email,display_name,status) VALUES($1,$2,'Synthetic relationship race operator','active')",[user,`relationship-race-${user}@example.invalid`]);
 await owner.query("INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES($1,$2,$3,'active')",[actor,org,user]);
 await owner.query("INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES($1,$2,$3,'Synthetic relationship race role','organization')",[role,org,`CI-REL-RACE-${role}`]);
 await owner.query("INSERT INTO eogp.role_permissions SELECT $1,$2,code FROM unnest(ARRAY['guest.registry.read','guest.registry.manage','guest.registry.merge','guest.registry.relationships.manage']) code",[org,role]);
 await owner.query("INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES($1,$2,$3,'organization',$2)",[org,actor,role]);
 const people=[];
 for(const lastName of ['Race source','Race destination','Race related']){
  const {rows}=await owner.query("SELECT eogp.write_guest_registry_person($1,$2,NULL,NULL,'create',$3::jsonb) AS data",[org,actor,JSON.stringify({firstName:'Synthetic',lastName})]);people.push(rows[0].data.personId);
 }
 const [source,destination,third]=people;
 const {rows:links}=await owner.query("SELECT eogp.write_guest_registry_relationship($1,$2,$3,NULL,$4,'family','mutual') AS data",[org,actor,source,third]);const link=links[0].data.relationshipId;
 await owner.query('COMMIT');
 const connect=async()=>{const c=new pg.Client({connectionString:process.env.DATABASE_URL_RUNTIME});await c.connect();sessions.push(c);await c.query("SET statement_timeout='10s'");await c.query('BEGIN');await c.query("SELECT set_config('app.organization_id',$1,true),set_config('app.actor_membership_id',$2,true)",[org,actor]);return c;};
 const observer=await connect();
 await observer.query("SELECT set_config('app.organization_id',$1,false),set_config('app.actor_membership_id',$2,false)",[org,actor]);
 const waitForLock=async pid=>{
  for(let n=0;n<100;n++){
   const {rows}=await observer.query('SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1',[pid]);
   if(rows[0]?.wait_event_type==='Lock')return;
   await new Promise(resolve=>setTimeout(resolve,25));
  }
  throw new Error('Expected concurrent merge to wait on the held relationship boundary');
 };
 const mergeSql="SELECT eogp.commit_guest_registry_merge($1,$2,$3,$4,1,1,'duplicate_profile',$5,NULL,NULL,NULL,'move_to_destination')";
 const review=async()=>{const {rows}=await observer.query('SELECT eogp.preview_guest_registry_merge($1,$2,$3,$4) AS data',[org,actor,source,destination]);return rows[0].data.reviewId;};
 let reviewId=await review();await observer.query('COMMIT');
 // Existing link ends while holding its row; merge must wait, then reject its old review.
 const ending=await connect();const merging=await connect();
 await ending.query('SELECT eogp.write_guest_registry_relationship($1,$2,$3,$4,NULL,NULL,NULL)',[org,actor,source,link]);
 let attempt=merging.query(mergeSql,[org,actor,source,destination,reviewId]).then(result=>({result}),error=>({error}));
 try{await waitForLock(merging.processID);}finally{await ending.query('COMMIT');}
 assert.equal((await attempt).error?.code,'40001','concurrent end did not invalidate the actor-bound review');await merging.query('ROLLBACK');
 // Recreate an active source link, review, then commit a conflicting destination link first.
 const setup=await connect();await setup.query("SELECT eogp.write_guest_registry_relationship($1,$2,$3,NULL,$4,'family','mutual')",[org,actor,source,third]);await setup.query('COMMIT');
 reviewId=await review();const creating=await connect();const mergingAgain=await connect();
 await creating.query("SELECT eogp.write_guest_registry_relationship($1,$2,$3,NULL,$4,'family','mutual')",[org,actor,destination,third]);
 attempt=mergingAgain.query(mergeSql,[org,actor,source,destination,reviewId]).then(result=>({result}),error=>({error}));
 try{await waitForLock(mergingAgain.processID);}finally{await creating.query('COMMIT');}
 assert.equal((await attempt).error?.code,'55000','concurrent destination duplicate was merged');await mergingAgain.query('ROLLBACK');
 const {rows}=await observer.query('SELECT eogp.preview_guest_registry_merge($1,$2,$3,$4) AS data',[org,actor,source,destination]);
 assert.equal(rows[0].data.source.status,'active');assert.equal(rows[0].data.blocker,'relationship_conflict');
 console.log('PASS concurrent relationship end and destination creation serialize against reviewed merges without partial identity changes');
}finally{
 await Promise.allSettled(sessions.map(async c=>{await c.query('ROLLBACK');await c.end();}));await owner.end();
}
