-- Expected: active admin/moderator helpers pass; moderator list excludes admin/moderator/self;
-- details keys are only about and username; non-active callers are rejected.
WITH claim AS MATERIALIZED (
 SELECT set_config('request.jwt.claim.sub',(SELECT user_id::text FROM private.moderator_users LIMIT 1),true)
)
SELECT public.mithaq_is_moderator() AS moderator_helper,
       public.mithaq_is_admin() AS not_admin,
       (SELECT count(*) FROM public.mithaq_moderator_list_members() m JOIN private.admin_users a ON a.user_id=m.id) AS admins_visible,
       (SELECT count(*) FROM public.mithaq_moderator_list_members() m JOIN private.moderator_users x ON x.user_id=m.id) AS moderators_visible,
       (SELECT array_agg(DISTINCT k.key ORDER BY k.key) FROM public.mithaq_moderator_list_members() m CROSS JOIN LATERAL jsonb_object_keys(m.details) k(key)) AS details_keys
FROM claim;

-- Negative tests: no real account is used and no member rows are modified.
DO $test$
DECLARE blocked integer := 0;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  BEGIN PERFORM 1 FROM public.mithaq_home_feed(); RAISE EXCEPTION 'home_feed_guard_failed'; EXCEPTION WHEN insufficient_privilege THEN blocked:=blocked+1; END;
  BEGIN PERFORM 1 FROM public.mithaq_public_member_profiles_v2(NULL); RAISE EXCEPTION 'profiles_guard_failed'; EXCEPTION WHEN insufficient_privilege THEN blocked:=blocked+1; END;
  BEGIN PERFORM 1 FROM public.mithaq_list_interested_by(); RAISE EXCEPTION 'interested_by_guard_failed'; EXCEPTION WHEN insufficient_privilege THEN blocked:=blocked+1; END;
  BEGIN PERFORM public.mithaq_get_member_actions('00000000-0000-0000-0000-000000000002'::uuid); RAISE EXCEPTION 'actions_guard_failed'; EXCEPTION WHEN insufficient_privilege THEN blocked:=blocked+1; END;
  BEGIN PERFORM public.mithaq_mark_messages_read('00000000-0000-0000-0000-000000000002'::uuid); RAISE EXCEPTION 'mark_read_guard_failed'; EXCEPTION WHEN insufficient_privilege THEN blocked:=blocked+1; END;
  IF blocked<>5 THEN RAISE EXCEPTION 'expected 5 denied operations, got %',blocked; END IF;
END;
$test$;
