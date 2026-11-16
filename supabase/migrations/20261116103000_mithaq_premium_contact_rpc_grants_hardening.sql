-- Restrict premium-contact RPCs to signed-in members.
-- PostgreSQL grants EXECUTE on newly created functions to PUBLIC by default.
-- The public list RPC returns contact phone numbers, so it must not be callable
-- by unauthenticated visitors. Admin RPCs also retain their in-function
-- mithaq_is_admin() checks as defense in depth.
REVOKE ALL ON FUNCTION public.mithaq_premium_contacts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mithaq_premium_contacts() TO authenticated;

REVOKE ALL ON FUNCTION public.mithaq_manage_premium_contact(text, uuid, text, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mithaq_manage_premium_contact(text, uuid, text, text, boolean) TO authenticated;

REVOKE ALL ON FUNCTION public.mithaq_premium_contacts_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mithaq_premium_contacts_admin() TO authenticated;

-- Intentionally leave mithaq_record_site_visit(uuid, uuid) available to anon:
-- the public landing page records anonymous visits using random visitor/session IDs.
