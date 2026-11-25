import assert from "node:assert/strict";
import test from "node:test";
import type {Pool} from "pg";
import {buildApi} from "../src/server.js";
const org="10000000-0000-0000-0000-00000000000a",actor="30000000-0000-0000-0000-00000000000a";
const event="79c00000-0000-4000-8000-00000000000a",booking="79c00000-0000-4000-8000-00000000000b",source="79c00000-0000-4000-8000-00000000000c",receipt="79c00000-0000-4000-8000-00000000000d";
for(const acknowledge of [false,true])test(`event disruption ${acknowledge?"acknowledgement":"publication"} canonical retry rechecks current authority`,async()=>{
 let stored:{request_sha256:unknown;response_status:unknown;response_body:unknown}|null=null,revoked=false,calls=0;
 const scope=acknowledge?[org,receipt,actor]:[org,event,actor,booking,source];
 const command=acknowledge?"acknowledge_event_disruption":"publish_local_event_disruption";
 const permission=acknowledge?"assert_event_disruption_receipt_permission":"assert_local_disruption_publication";
 const client={async query(sql:string,values:readonly unknown[]=[]){
  if(sql.startsWith("SELECT request_sha256"))return{rows:stored?[stored]:[]};
  if(sql.startsWith("INSERT INTO eogp.idempotency_records")){stored={request_sha256:values[4],response_status:null,response_body:null};return{rows:[{id:receipt}]};}
  if(sql.startsWith("UPDATE eogp.idempotency_records"))stored={request_sha256:values[4],response_status:values[5],response_body:values[6]};
  if(sql.includes(`SELECT eogp.${permission}`)){assert.deepEqual(values,scope);if(revoked)throw Object.assign(new Error("private synthetic authority detail"),{code:"42501"});}
  if(sql.includes(`SELECT eogp.${command}`)){assert.deepEqual(values,scope);calls++;return{rows:[{result:{noticeId:receipt,status:acknowledge?"acknowledged":"received"}}]};}
  return{rows:[]};
 },release(){}};
 const app=buildApi({pool:{connect:async()=>client} as unknown as Pool,authenticateStaff:async()=>({organizationId:org,membershipId:actor,userId:org}),verifyMutationOrigin:async()=>true});
 const path=(id:string)=>acknowledge?`/event-disruption-notices/${id}/acknowledge`:`/events/${id}/disruption-notices`;
 const id=acknowledge?receipt:event;const payload=acknowledge?{}:{bookingId:booking,sourceBookingNoticeId:source};
 const request={method:"POST" as const,url:path(id.toUpperCase()),headers:{"idempotency-key":`synthetic-inbox-${acknowledge}`},payload:acknowledge?{}:{bookingId:booking.toUpperCase(),sourceBookingNoticeId:source.toUpperCase()}};
 try{
  const first=await app.inject(request);assert.equal(first.statusCode,acknowledge?200:201,first.body);assert.match(first.headers["cache-control"]??"",/no-store/);
  const replay=await app.inject({...request,url:path(id),payload});assert.equal(replay.statusCode,first.statusCode,replay.body);assert.equal(calls,1);
  assert.equal((await app.inject({...request,payload:{...payload,actorMembershipId:org}})).statusCode,first.statusCode);
  revoked=true;const denied=await app.inject(request);assert.equal(denied.statusCode,403,denied.body);assert.ok(!denied.body.includes("private synthetic authority detail"));assert.equal(calls,1);
 }finally{await app.close();}
});
test("event disruption history bounds and source/receipt identities stay explicit",async()=>{
 let reads=0;
 const client={async query(sql:string,values:readonly unknown[]=[]){
  if(sql.includes("SELECT eogp.list_event_disruption_notices")){reads++;assert.deepEqual(values,[org,actor,event,50]);return{rows:[{result:{notices:[{noticeId:receipt,sourceBookingNoticeId:source}],nextOffset:null}}]};}
  return{rows:[]};
 },release(){}};
 const app=buildApi({pool:{connect:async()=>client} as unknown as Pool,authenticateStaff:async()=>({organizationId:org,membershipId:actor,userId:org}),verifyMutationOrigin:async()=>true});
 try{
  const result=await app.inject({method:"GET",url:`/events/${event}/disruption-notices?offset=50`});assert.equal(result.statusCode,200,result.body);assert.equal(result.json().data.notices[0].noticeId,receipt);assert.equal(result.json().data.notices[0].sourceBookingNoticeId,source);assert.match(result.headers["cache-control"]??"",/no-store/);
  assert.equal((await app.inject({method:"GET",url:`/events/${event}/disruption-notices?offset=100001`})).statusCode,400);assert.equal(reads,1);
  assert.equal((await app.inject({method:"POST",url:`/events/${event}/disruption-notices`,headers:{"idempotency-key":"invalid-source"},payload:{bookingId:booking,sourceBookingNoticeId:"not-a-uuid"}})).statusCode,400);
 }finally{await app.close();}
});
