import assert from "node:assert/strict";
import test from "node:test";
import type {Pool} from "pg";
import {buildApi} from "../src/server.js";
const org="10000000-0000-0000-0000-00000000000a",recipient="10000000-0000-0000-0000-00000000000b",actor="30000000-0000-0000-0000-00000000000a",booking="f0000000-0000-0000-0000-00000000000a";
test("booking proposal retries normalize identity, purpose and dates and recheck both authorities",async()=>{
 let stored:{request_sha256:unknown;response_status:unknown;response_body:unknown}|null=null,calls=0,revoked=false;
 const client={async query(sql:string,values:readonly unknown[]=[]){
  if(sql.startsWith("SELECT request_sha256"))return{rows:stored?[stored]:[]};
  if(sql.startsWith("INSERT INTO eogp.idempotency_records")){stored={request_sha256:values[4],response_status:null,response_body:null};return{rows:[{id:booking}]};}
  if(sql.startsWith("UPDATE eogp.idempotency_records"))stored={request_sha256:values[4],response_status:values[5],response_body:values[6]};
  if(sql.includes("SELECT eogp.assert_booking_collaboration_proposal_permission")){assert.deepEqual(values,[org,booking,actor]);if(revoked)throw Object.assign(new Error("private source permission"),{code:"42501"});}
  if(sql.includes("SELECT eogp.propose_booking_collaboration")){calls++;assert.deepEqual(values.slice(0,3),[org,booking,actor]);assert.deepEqual(values.slice(4),[recipient,"Synthetic purpose","2027-01-01T10:00:00.000Z",null]);return{rows:[{result:{grantId:values[3],status:"proposed"}}]};}
  return{rows:[]};
 },release(){}};
 const app=buildApi({pool:{connect:async()=>client} as unknown as Pool,authenticateStaff:async()=>({organizationId:org,membershipId:actor,userId:org}),verifyMutationOrigin:async()=>true});
 const request={method:"POST" as const,url:`/bookings/${booking.toUpperCase()}/collaboration-grants`,headers:{"idempotency-key":"synthetic-booking-proposal"},payload:{granteeOrganizationId:recipient.toUpperCase(),purpose:" Synthetic purpose ",validFrom:"2027-01-01T11:00:00+01:00",validUntil:null}};
 try{
  const first=await app.inject(request);assert.equal(first.statusCode,201,first.body);assert.match(first.headers["cache-control"]??"",/no-store/);
  const replay=await app.inject({...request,url:request.url.toLowerCase(),payload:{...request.payload,granteeOrganizationId:recipient,purpose:"Synthetic purpose",validFrom:"2027-01-01T10:00:00Z"}});assert.equal(replay.statusCode,201,replay.body);assert.equal(replay.json().data.grantId,first.json().data.grantId);assert.equal(calls,1);
  revoked=true;const denied=await app.inject(request);assert.equal(denied.statusCode,403);assert.ok(!denied.body.includes("private source permission"));assert.equal(calls,1);
  for(const payload of [{...request.payload,granteeOrganizationId:org},{...request.payload,purpose:" "},{...request.payload,validUntil:"2026-01-01T00:00:00Z"}])assert.equal((await app.inject({...request,payload})).statusCode,400);
  const {validUntil:_omitted,...missingExpiry}=request.payload;assert.equal((await app.inject({...request,payload:missingExpiry})).statusCode,400);
 }finally{await app.close();}
});
