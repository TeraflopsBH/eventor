-- This script must connect through WORKER_URL (session_user=eventor_worker).
BEGIN;
SELECT set_config('app.organization_id','22222222-2222-4222-8222-222222222222',true);
SELECT * FROM eogp.claim_invitation_email_delivery('22222222-2222-4222-8222-222222222222');
COMMIT;
