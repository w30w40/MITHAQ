-- Read-only verification: expected search_path=\"\" and authenticated EXECUTE remains true.
SELECT p.proname,p.proconfig,
       has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_can_execute
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='mithaq_admin_review_bio';
