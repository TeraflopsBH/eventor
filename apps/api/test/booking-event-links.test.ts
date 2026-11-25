import assert from "node:assert/strict";
import test from "node:test";
import type {Pool} from "pg";
import {buildApi} from "../src/server.js";
const organizationId="10000000-0000-0000-0000-00000000000b",membershipId="30000000-0000-0000-0000-00000000000b";
const eventId="79a00000-0000-4000-8000-000000000001",bookingId="79a00000-0000-4000-8000-000000000002",grantId="79a00000-0000-4000-8000-000000000003",linkId="79a00000-0000-4000-8000-000000000004";
for(const crossOrganization of [false,true]){
 test(`booking association ${crossOrganization?"cross-organization":"same-organization"} retry normalizes IDs and rechecks authority`,async()=>{
  let stored:{request_sha256:unknown;response_status:unknown;response_body:unknown}|null=null;let revoked=false;let calls=0;
  const owner=crossOrganization?"10000000-0000-0000-0000-00000000000a":organizationId;
  const valuesExpected=[organizationId,eventId,membershipId,owner,bookingId,crossOrganization?grantId:null];
  const client={async query(sql:string,values:readonly unknown[]=[]){
   if(sql.startsWith("SELECT request_sha256"))return{rows:stored?[stored]:[]};
   if(sql.startsWith("INSERT INTO eogp.idempotency_records")){stored={request_sha256:values[4],response_status:null,response_body:null};return{rows:[{id:linkId}]};}
   if(sql.startsWith("UPDATE eogp.idempotency_records"))stored={request_sha256:values[4],response_status:values[5],response_body:values[6]};
   if(sql.includes("SELECT eogp.assert_event_booking_link_permission")){
    assert.deepEqual(values,valuesExpected);if(revoked)throw Object.assign(new Error("synthetic private permission detail"),{code:"42501"});
   }
   if(sql.includes("SELECT eogp.create_event_booking_link")){calls++;assert.deepEqual(values,[...valuesExpected,"venue_for_event"]);return{rows:[{result:{linkId,status:"active"}}]};}
   return{rows:[]};
  },release(){}};
  const app=buildApi({pool:{connect:async()=>client} as unknown as Pool,authenticateStaff:async()=>({organizationId,membershipId,userId:"20000000-0000-0000-0000-00000000000b"}),verifyMutationOrigin:async()=>true});
  const request={method:"POST" as const,url:`/events/${eventId.toUpperCase()}/booking-links`,headers:{"idempotency-key":`synthetic-link-${crossOrganization}`},payload:{bookingOwnerOrganizationId:owner.toUpperCase(),bookingId:bookingId.toUpperCase(),relationshipKind:"venue_for_event",...(crossOrganization?{collaborationGrantId:grantId.toUpperCase()}:{})}};
  try{
   const first=await app.inject(request);assert.equal(first.statusCode,201,first.body);assert.match(first.headers["cache-control"]??"",/no-store/);
   const replay=await app.inject({...request,url:`/events/${eventId}/booking-links`,payload:{...request.payload,bookingOwnerOrganizationId:owner,bookingId,collaborationGrantId:crossOrganization?grantId:null}});assert.equal(replay.statusCode,201,replay.body);assert.equal(calls,1);
   revoked=true;const denied=await app.inject(request);assert.equal(denied.statusCode,403,denied.body);assert.equal(calls,1);assert.ok(!denied.body.includes("synthetic private permission detail"));
  }finally{await app.close();}
 });
}

test("event association page passes selected tenant/actor and rejects invalid page input",async()=>{
 let reads=0;
 const client={async query(sql:string,values:readonly unknown[]=[]){
  if(sql.includes("SELECT eogp.list_event_booking_links")){reads++;assert.deepEqual(values,[organizationId,membershipId,eventId,50]);return{rows:[{result:{links:[],nextOffset:null}}]};}
  return{rows:[]};
 },release(){}};
 const app=buildApi({pool:{connect:async()=>client} as unknown as Pool,authenticateStaff:async()=>({organizationId,membershipId,userId:"20000000-0000-0000-0000-00000000000b"}),verifyMutationOrigin:async()=>true});
 try{
  const response=await app.inject({method:"GET",url:`/events/${eventId}/booking-links?offset=50`});assert.equal(response.statusCode,200,response.body);assert.deepEqual(response.json().data,{links:[],nextOffset:null});
  assert.equal((await app.inject({method:"GET",url:`/events/${eventId}/booking-links?offset=-1`})).statusCode,400);assert.equal(reads,1);
  assert.equal((await app.inject({method:"POST",url:`/events/${eventId}/booking-links`,headers:{"idempotency-key":"invalid-link-fixture"},payload:{bookingOwnerOrganizationId:organizationId,bookingId,relationshipKind:"unsupported"}})).statusCode,400);
 }finally{await app.close();}
});

test("booking reference lookup forwards only selected-organization context and validates search bounds",async()=>{
 let reads=0;
 const client={async query(sql:string,values:readonly unknown[]=[]){
  if(sql.includes("SELECT eogp.list_booking_disruption_workspace")){reads++;assert.deepEqual(values,[organizationId,membershipId,0,"Synthetic"]);return{rows:[{result:{bookings:[{bookingId,bookingCode:"Synthetic reference",status:"confirmed"}],nextOffset:null}}]};}
  return{rows:[]};
 },release(){}};
 const app=buildApi({pool:{connect:async()=>client} as unknown as Pool,authenticateStaff:async()=>({organizationId,membershipId,userId:"20000000-0000-0000-0000-00000000000b"}),verifyMutationOrigin:async()=>true});
 try{
  const url=`/organizations/${organizationId}/booking-references/search`;
  const response=await app.inject({method:"POST",url,payload:{query:"Synthetic"}});assert.equal(response.statusCode,200,response.body);assert.equal(response.json().data.bookings[0].bookingCode,"Synthetic reference");assert.match(response.headers["cache-control"]??"",/no-store/);
  assert.equal((await app.inject({method:"POST",url,payload:{query:"x".repeat(81)}})).statusCode,400);
  assert.equal((await app.inject({method:"POST",url,payload:{offset:-1}})).statusCode,400);
  assert.equal((await app.inject({method:"POST",url:"/organizations/10000000-0000-0000-0000-00000000000a/booking-references/search",payload:{query:"Synthetic"}})).statusCode,403);assert.equal(reads,1);
 }finally{await app.close();}
});

test("ending event association canonicalizes identity and rechecks event authority on cached retry",async()=>{
 let stored:{request_sha256:unknown;response_status:unknown;response_body:unknown}|null=null,revoked=false,calls=0;
 const scope=[organizationId,eventId,membershipId,linkId];
 const client={async query(sql:string,values:readonly unknown[]=[]){
  if(sql.startsWith("SELECT request_sha256"))return{rows:stored?[stored]:[]};
  if(sql.startsWith("INSERT INTO eogp.idempotency_records")){stored={request_sha256:values[4],response_status:null,response_body:null};return{rows:[{id:linkId}]};}
  if(sql.startsWith("UPDATE eogp.idempotency_records"))stored={request_sha256:values[4],response_status:values[5],response_body:values[6]};
  if(sql.includes("SELECT eogp.assert_event_booking_link_end_permission")){assert.deepEqual(values,scope);if(revoked)throw Object.assign(new Error("private ending authority detail"),{code:"42501"});}
  if(sql.includes("SELECT eogp.end_event_booking_link")){assert.deepEqual(values,scope);calls++;return{rows:[{result:{linkId,status:"ended"}}]};}
  return{rows:[]};
 },release(){}};
 const app=buildApi({pool:{connect:async()=>client} as unknown as Pool,authenticateStaff:async()=>({organizationId,membershipId,userId:organizationId}),verifyMutationOrigin:async()=>true});
 const request={method:"POST" as const,url:`/events/${eventId.toUpperCase()}/booking-links/${linkId.toUpperCase()}/end`,headers:{"idempotency-key":"synthetic-link-ending-retry"},payload:{}};
 try{
  const response=await app.inject(request);assert.equal(response.statusCode,200,response.body);assert.match(response.headers["cache-control"]??"",/no-store/);
  assert.equal((await app.inject({...request,url:request.url.toLowerCase()})).statusCode,200);assert.equal(calls,1);
  revoked=true;const denied=await app.inject(request);assert.equal(denied.statusCode,403,denied.body);assert.ok(!denied.body.includes("private ending authority detail"));assert.equal(calls,1);
  assert.equal((await app.inject({...request,url:`/events/${eventId}/booking-links/invalid/end`})).statusCode,400);
 }finally{await app.close();}
});
