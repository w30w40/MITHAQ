-- Remove retired member-number snapshots while preserving the audit event itself.
UPDATE private.mithaq_admin_ai_audit
SET before_data = CASE WHEN before_data IS NULL THEN NULL ELSE before_data - 'member_number' END,
    after_data = CASE WHEN after_data IS NULL THEN NULL ELSE after_data - 'member_number' END
WHERE target_schema = 'public'
  AND target_table = 'profiles'
  AND (
    COALESCE(before_data,'{}'::jsonb) ? 'member_number'
    OR COALESCE(after_data,'{}'::jsonb) ? 'member_number'
  );