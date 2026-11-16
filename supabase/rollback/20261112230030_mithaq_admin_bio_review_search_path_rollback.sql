-- Restores the previous function setting. Use only if a compatibility issue is proven.
ALTER FUNCTION public.mithaq_admin_review_bio(uuid, boolean)
SET search_path TO public, private, auth;
