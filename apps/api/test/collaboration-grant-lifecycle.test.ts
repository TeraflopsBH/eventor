import assert from "node:assert/strict";
import test from "node:test";
import type {Pool} from "pg";
import {buildApi} from "../src/server.js";
const org="10000000-0000-0000-0000-00000000000b",actor="30000000-0000-0000-0000-00000000000b",grant="79e00000-0000-4000-8000-00000000000a";
for(const action of ["accept","revoke"] as const)test(`collaboration ${action} canonical retries recheck current party/role/grant authority`,async()=>{
 let stored:{request_sha256:unknown;response_status:unknown;response_body:unknown}|null=null,calls=0,deniedCode:string|null=null;
 const scope=[org,actor,grant,action];const reason=action==="revoke"?"Synthetic revoke reason":null;
 const client={async query(sql:string,values:readonly unknown[]=[]){
  if(sql.startsWith("SELECT request_sha256"))return{rows:stored?[stored]:[]};
  if(sql.startsWith("INSERT INTO eogp.idempotency_records")){stored={request_sha256:values[4],response_status:null,response_body:null};return{rows:[{id:grant}]};}
  if(sql.startsWith("UPDATE eogp.idempotency_records"))stored={request_sha256:values[4],response_status:values[5],response_body:values[6]};
  if(sql.includes("SELECT eogp.assert_staff_collaboration_action")){assert.deepEqual(values,scope);if(deniedCode)throw Object.assign(new Error("private collaboration detail"),{code:deniedCode});}
  if(sql.includes("SELECT eogp.staff_collaboration_grant_action")){calls++;assert.deepEqual(values,[...scope,reason]);return{rows:[{result:{grantId:grant,status:action==="accept"?"active":"revoked"}}]};}
  return{rows:[]};
 },release(){}};
 const app=buildApi({pool:{connect:async()=>client} as unknown as Pool,authenticateStaff:async()=>({organizationId:org,membershipId:actor,userId:org}),verifyMutationOrigin:async()=>true});
 const request={method:"POST" as const,url:`/collaboration-grants/${grant.toUpperCase()}/${action}`,headers:{"idempotency-key":`synthetic-grant-${action}`},payload:action==="accept"?{}:{reason:` ${reason} `}};
 try{
  const first=await app.inject(request);assert.equal(first.statusCode,200,first.body);assert.match(first.headers["cache-control"]??"",/no-store/);
  const replay=await app.inject({...request,url:request.url.toLowerCase(),payload:action==="accept"?{}:{reason}});assert.equal(replay.statusCode,200,replay.body);assert.equal(calls,1);
  deniedCode="42501";const denied=await app.inject(request);assert.equal(denied.statusCode,403,denied.body);assert.ok(!denied.body.includes("private collaboration detail"));assert.equal(calls,1);
  deniedCode="55000";assert.equal((await app.inject(request)).statusCode,409,'unavailable grant returned cached active success');
  assert.equal((await app.inject({...request,url:`/collaboration-grants/not-a-uuid/${action}`})).statusCode,400);
  if(action==="revoke")for(const invalid of ["  ","bad\nreason", "x".repeat(2001)])assert.equal((await app.inject({...request,payload:{reason:invalid}})).statusCode,400);
 }finally{await app.close();}
});

test("collaboration list and detail pass selected party context and bound paging",async()=>{
 let reads=0;
 const client={async query(sql:string,values:readonly unknown[]=[]){
  if(sql.includes("SELECT eogp.list_staff_collaboration_grants")){reads++;assert.deepEqual(values,[org,actor,50]);return{rows:[{result:{grants:[{grantId:grant,status:"proposed"}],nextOffset:null}}]};}
  if(sql.includes("SELECT eogp.read_staff_collaboration_grant")){reads++;assert.deepEqual(values,[org,actor,grant]);return{rows:[{result:{grantId:grant,projection:{reviewLabel:"Synthetic shared configuration"}}}]};}
  return{rows:[]};
 },release(){}};
 const app=buildApi({pool:{connect:async()=>client} as unknown as Pool,authenticateStaff:async()=>({organizationId:org,membershipId:actor,userId:org}),verifyMutationOrigin:async()=>true});
 try{
  const path=`/organizations/${org}/collaboration-grants`;
  const response=await app.inject({method:"GET",url:path+'?offset=50'});assert.equal(response.statusCode,200,response.body);assert.equal(response.json().data.grants[0].grantId,grant);assert.match(response.headers["cache-control"]??"",/no-store/);
  const detail=await app.inject({method:"GET",url:`/collaboration-grants/${grant}`});assert.equal(detail.statusCode,200,detail.body);assert.equal(detail.json().data.projection.reviewLabel,"Synthetic shared configuration");assert.match(detail.headers["cache-control"]??"",/no-store/);
  for(const offset of [-1,100001])assert.equal((await app.inject({method:"GET",url:path+`?offset=${offset}`})).statusCode,400);
  assert.equal((await app.inject({method:"GET",url:'/organizations/10000000-0000-0000-0000-00000000000a/collaboration-grants'})).statusCode,403);assert.equal(reads,2);
 }finally{await app.close();}
});
