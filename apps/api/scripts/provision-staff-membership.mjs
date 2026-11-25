// Host-only command. This does not accept or change credentials or role grants.
import {parseArgs} from 'node:util';
import pg from 'pg';
import {provisionStaffMembership,StaffMembershipError} from '../dist/src/staff-membership-provisioning.js';
let pool;
try{
 const {values}=parseArgs({options:{email:{type:'string'},organization:{type:'string'},reason:{type:'string'},help:{type:'boolean'}},strict:true,allowPositionals:false});
 if(values.help)console.log('Usage: scripts/admin/provision-staff-membership.sh --email EMAIL --organization UUID --reason REASON\nRequires MIGRATOR_URL and the built API. Creates one membership for an existing active account in an active organization. Existing memberships are refused. Credentials, other workspaces, roles and platform authority are unchanged.');
 else{
  if(!process.env.MIGRATOR_URL || !values.email || !values.organization || !values.reason)throw new Error('Missing provisioning input');
  pool=new pg.Pool({connectionString:process.env.MIGRATOR_URL,max:1});
  const result=await provisionStaffMembership(pool,{email:values.email,organizationId:values.organization,reason:values.reason});
  console.log(JSON.stringify({...result,rolesGranted:false,accountChanged:false}));
 }
}catch(failure){console.error(failure instanceof StaffMembershipError?failure.message:'Membership provisioning failed. Check the arguments and privileged database connection.');process.exitCode=1;}
finally{if(pool)await pool.end();}
