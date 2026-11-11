\set ON_ERROR_STOP on

-- Synthetic global identities are inserted through the dedicated auth role,
-- before the normal runtime-role tenant fixtures are created.
INSERT INTO eogp.users (id, email, display_name, status)
VALUES
 ('20000000-0000-0000-0000-00000000000a','ci-extended-a@example.invalid','CI A','active'),
 ('20000000-0000-0000-0000-00000000000b','ci-extended-b@example.invalid','CI B','active'),
 ('20000000-0000-0000-0000-00000000000c','ci-extended-c@example.invalid','CI C','active');

\echo 'Synthetic authentication identities seeded.'
