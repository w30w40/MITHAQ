-- Read-only verification for migration 20261112225851_mithaq_security_hardening_20261113.
SELECT
  has_table_privilege('authenticated','public.mithaq_notifications','TRUNCATE') AS notifications_truncate_must_be_false,
  has_table_privilege('authenticated','public.mithaq_push_subscriptions','TRUNCATE') AS push_truncate_must_be_false,
  has_column_privilege('authenticated','public.mithaq_notifications','read_at','UPDATE') AS read_at_update_must_be_true,
  has_column_privilege('authenticated','public.mithaq_notifications','recipient_id','UPDATE') AS recipient_id_update_must_be_false;

-- This tests the moderator RPC using an existing moderator identity without returning
-- any member values. Expected keys: {about, username}.
WITH moderator_claim AS MATERIALIZED (
  SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT user_id::text FROM private.moderator_users ORDER BY user_id LIMIT 1),
    true
  )
)
SELECT array_agg(DISTINCT k.key ORDER BY k.key) AS returned_detail_keys
FROM moderator_claim
CROSS JOIN LATERAL public.mithaq_moderator_list_members() AS m
CROSS JOIN LATERAL jsonb_object_keys(m.details) AS k(key);
