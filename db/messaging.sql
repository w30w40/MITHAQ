CREATE TABLE IF NOT EXISTS public.messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  recipient_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  body text NOT NULL CHECK (char_length(trim(body)) BETWEEN 1 AND 2000),
  created_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz,
  CONSTRAINT messages_no_self_message CHECK (sender_id <> recipient_id)
);

CREATE INDEX IF NOT EXISTS messages_sender_created_idx
  ON public.messages (sender_id, created_at DESC);
CREATE INDEX IF NOT EXISTS messages_recipient_created_idx
  ON public.messages (recipient_id, created_at DESC);

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "participants can read accepted conversations" ON public.messages;
CREATE POLICY "participants can read accepted conversations"
ON public.messages FOR SELECT TO authenticated
USING (
  (sender_id = auth.uid() OR recipient_id = auth.uid())
  AND EXISTS (
    SELECT 1 FROM public.contact_consent_requests r
    WHERE r.access_status = 'accepted'
      AND (
        (r.requester_id = public.messages.sender_id AND r.recipient_id = public.messages.recipient_id)
        OR
        (r.requester_id = public.messages.recipient_id AND r.recipient_id = public.messages.sender_id)
      )
  )
);

DROP POLICY IF EXISTS "send messages in accepted conversations" ON public.messages;
CREATE POLICY "send messages in accepted conversations"
ON public.messages FOR INSERT TO authenticated
WITH CHECK (
  sender_id = auth.uid()
  AND EXISTS (
    SELECT 1 FROM public.contact_consent_requests r
    WHERE r.access_status = 'accepted'
      AND (
        (r.requester_id = public.messages.sender_id AND r.recipient_id = public.messages.recipient_id)
        OR
        (r.requester_id = public.messages.recipient_id AND r.recipient_id = public.messages.sender_id)
      )
  )
);

REVOKE ALL ON public.messages FROM anon;
GRANT SELECT, INSERT ON public.messages TO authenticated;