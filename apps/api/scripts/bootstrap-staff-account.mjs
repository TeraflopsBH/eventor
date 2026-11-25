// Host-only entry point: passwords arrive on stdin, never as command arguments.
import {parseArgs} from 'node:util';
import pg from 'pg';
import {bootstrapStaffAccount} from '../dist/src/staff-account-bootstrap.js';
let pool;
try {
 const {values}=parseArgs({options:{email:{type:'string'},name:{type:'string'},organization:{type:'string'},reason:{type:'string'},help:{type:'boolean'}},strict:true,allowPositionals:false});
 if(values.help){console.log('Usage: scripts/admin/bootstrap-staff-account.sh --email EMAIL --name NAME [--organization UUID] --reason REASON\nRequires MIGRATOR_URL and the built API. Password is read from stdin or prompted securely by the shell wrapper. No roles or platform privileges are granted.');}
 else {
  if(!process.env.MIGRATOR_URL)throw new Error('Set MIGRATOR_URL to the privileged migration connection.');
  if(!values.email||!values.name||!values.reason)throw new Error('Specify --email, --name and --reason.');
  if(process.stdin.isTTY)throw new Error('Use scripts/admin/bootstrap-staff-account.sh for hidden password entry.');
  const chunks=[];let bytes=0;for await(const chunk of process.stdin){bytes+=chunk.length;if(bytes>1026)throw new Error('Password input is too long.');chunks.push(chunk);}
  const encoded=Buffer.concat(chunks);const decoded=encoded.toString('utf8');if(!encoded.equals(Buffer.from(decoded,'utf8')))throw new Error('Password input must be valid UTF-8.');
  const password=decoded.replace(/\r?\n$/u,'');
  pool=new pg.Pool({connectionString:process.env.MIGRATOR_URL,max:1});
  const result=await bootstrapStaffAccount(pool,{email:values.email,displayName:values.name,password,reason:values.reason,...(values.organization!==undefined?{organizationId:values.organization}:{})});
  console.log(JSON.stringify({...result,rolesGranted:false,platformAdmin:false}));
 }
}catch(failure){console.error(failure?.name==='StaffBootstrapError'?failure.message:'Bootstrap failed. Check the arguments, password input and privileged database connection.');process.exitCode=1;}
finally{if(pool)await pool.end();}
