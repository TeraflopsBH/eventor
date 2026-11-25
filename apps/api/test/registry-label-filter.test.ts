import assert from "node:assert/strict";
import test from "node:test";
import type { Pool } from "pg";
import {buildApi} from "../src/server.js";
const organizationId="10000000-0000-0000-0000-00000000000a",membershipId="30000000-0000-0000-0000-00000000000a",labelId="79000000-0000-4000-8000-000000000001";
for(const mode of ["search","export"] as const){
 test(`Registry ${mode} forwards a validated classification filter and preserves null compatibility`,async()=>{
  const calls:unknown[][]=[];
  const client={async query(sql:string,values:readonly unknown[]=[]){
   if(sql.includes("SELECT eogp.read_guest_registry")){
    calls.push([...values]);return{rows:[{result:{people:[],canManage:false,canMerge:false,canExport:mode==="export",nextOffset:null}}]};
   }
   return{rows:[]};
  },release(){}};
  const app=buildApi({pool:{connect:async()=>client} as unknown as Pool,authenticateStaff:async()=>({organizationId,membershipId,userId:"20000000-0000-0000-0000-00000000000a"}),verifyMutationOrigin:async()=>true});
  try{
   for(const filter of [labelId,null]){
    const response=await app.inject({method:"POST",url:`/organizations/${organizationId}/persons/${mode}`,payload:{query:"Synthetic",archived:true,...(filter?{labelId:filter}:{})}});
    assert.equal(response.statusCode,200,response.body);assert.match(response.headers["cache-control"]??"",/no-store/);
    assert.deepEqual(calls.at(-1),mode==="search"?[organizationId,membershipId,null,"Synthetic",true,0,filter]:[organizationId,membershipId,"Synthetic",true,filter]);
   }
   const invalid=await app.inject({method:"POST",url:`/organizations/${organizationId}/persons/${mode}`,payload:{labelId:"invalid"}});
   assert.equal(invalid.statusCode,400);assert.equal(calls.length,2);
  }finally{await app.close();}
 });
}

test("Registry classification options enforce Registry authority and sanitize a denial",async()=>{
 let revoked=false;
 const client={async query(sql:string){
  if(sql.includes("list_registry_labels")){
   if(revoked)throw Object.assign(new Error("synthetic private label information"),{code:"42501"});
   return{rows:[{result:[{labelId,label:"Synthetic VIP",retired:true}]}]};
  }
  return{rows:[]};
 },release(){}};
 const app=buildApi({pool:{connect:async()=>client} as unknown as Pool,authenticateStaff:async()=>({organizationId,membershipId,userId:"20000000-0000-0000-0000-00000000000a"}),verifyMutationOrigin:async()=>true});
 try{
  const response=await app.inject({method:"GET",url:`/organizations/${organizationId}/persons/labels`});assert.equal(response.statusCode,200,response.body);assert.equal(response.json().data[0].retired,true);
  const foreign=await app.inject({method:"GET",url:"/organizations/10000000-0000-0000-0000-00000000000b/persons/labels"});assert.equal(foreign.statusCode,403);
  revoked=true;const denied=await app.inject({method:"GET",url:`/organizations/${organizationId}/persons/labels`});assert.equal(denied.statusCode,403);assert.ok(!denied.body.includes("synthetic private label information"));
 }finally{await app.close();}
});
