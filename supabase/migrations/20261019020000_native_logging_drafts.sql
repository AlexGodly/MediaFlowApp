-- Additive, isolated native Logging draft storage.
-- NEVER touches public.mediaflow_states, History, XP or website state.
CREATE TABLE IF NOT EXISTS public.mediaflow_native_logging_drafts (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  revision bigint NOT NULL DEFAULT 1 CHECK (revision >= 1),
  draft_data jsonb NOT NULL DEFAULT '{"format":"mediaflow-native-logging-draft-v1","entries":[],"keepTitles":true}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT mediaflow_native_draft_format CHECK (
    jsonb_typeof(draft_data) = 'object'
    AND draft_data->>'format' = 'mediaflow-native-logging-draft-v1'
    AND jsonb_typeof(draft_data->'entries') = 'array'
    AND jsonb_array_length(draft_data->'entries') <= 300
    AND pg_column_size(draft_data) <= 1048576
  )
);
ALTER TABLE public.mediaflow_native_logging_drafts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.mediaflow_native_logging_drafts FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.mediaflow_native_logging_drafts TO authenticated;
DROP POLICY IF EXISTS "mf_native_draft_read_own" ON public.mediaflow_native_logging_drafts;
CREATE POLICY "mf_native_draft_read_own" ON public.mediaflow_native_logging_drafts
  FOR SELECT TO authenticated USING ((select auth.uid()) = user_id);
DROP POLICY IF EXISTS "mf_native_draft_insert_own" ON public.mediaflow_native_logging_drafts;
CREATE POLICY "mf_native_draft_insert_own" ON public.mediaflow_native_logging_drafts
  FOR INSERT TO authenticated WITH CHECK ((select auth.uid()) = user_id);
DROP POLICY IF EXISTS "mf_native_draft_update_own" ON public.mediaflow_native_logging_drafts;
CREATE POLICY "mf_native_draft_update_own" ON public.mediaflow_native_logging_drafts
  FOR UPDATE TO authenticated
  USING ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);
COMMENT ON TABLE public.mediaflow_native_logging_drafts IS
  'Native Flutter Advanced Logging drafts only. Not submitted consumption logs. Legacy website state remains authoritative.';
