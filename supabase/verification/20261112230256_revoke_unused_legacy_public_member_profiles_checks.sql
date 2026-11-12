-- The unused legacy RPC must be inaccessible; the current v2 RPC remains available.
SELECT
  has_function_privilege('authenticated','public.mithaq_public_member_profiles(uuid[])','EXECUTE') AS legacy_authenticated_execute_must_be_false,
  has_function_privilege('anon','public.mithaq_public_member_profiles(uuid[])','EXECUTE') AS legacy_anon_execute_must_be_false,
  has_function_privilege('authenticated','public.mithaq_public_member_profiles_v2(uuid[])','EXECUTE') AS v2_authenticated_execute_must_be_true;
