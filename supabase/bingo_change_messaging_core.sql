-- ============================================================
-- DRAFT MIGRATION — Bingo Internal Messaging Core Schema
-- Status: DRAFT ONLY. NOT APPLIED. Do not run against any Supabase project
-- without explicit approval. Written additively — creates new tables only,
-- does not touch any existing table (including the pre-existing `messages`
-- table used by the legacy seller-chat feature, which Packet M1 found has
-- no schema/RLS record in this repo and must be checked live before reuse).
-- ============================================================

-- Conversations -------------------------------------------------
create table if not exists bingo_conversations (
  id uuid primary key default gen_random_uuid(),
  type text not null default 'direct' check (type in ('direct','group')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  group_name text,
  group_photo_url text
);

-- Participants ----------------------------------------------------
create table if not exists bingo_conversation_participants (
  conversation_id uuid not null references bingo_conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  role text not null default 'member' check (role in ('member','admin')),
  joined_at timestamptz not null default now(),
  last_read_message_id uuid,
  archived_at timestamptz,
  pinned_at timestamptz,
  muted_until timestamptz,
  calls_muted_until timestamptz,
  deleted_at timestamptz,
  purge_after timestamptz,
  primary key (conversation_id, user_id)
);

-- Messages ----------------------------------------------------------
create table if not exists bingo_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references bingo_conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id),
  type text not null default 'text' check (type in ('text','image','video','audio','voice_note','document','sticker','profile_card','listing_card')),
  body text,
  reply_to_message_id uuid references bingo_messages(id),
  forwarded_from_message_id uuid references bingo_messages(id),
  client_generated_id text, -- for idempotent optimistic-send de-duplication
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  unsent_at timestamptz
);
create index if not exists idx_bingo_messages_conversation on bingo_messages(conversation_id, created_at desc);
create unique index if not exists idx_bingo_messages_client_id on bingo_messages(conversation_id, sender_id, client_generated_id) where client_generated_id is not null;

-- Attachments -----------------------------------------------------
create table if not exists bingo_message_attachments (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references bingo_messages(id) on delete cascade,
  storage_path text not null,
  media_type text not null check (media_type in ('image','video','audio','document')),
  mime_type text,
  size bigint,
  duration numeric,
  metadata jsonb default '{}'::jsonb
);

-- Reactions ---------------------------------------------------------
create table if not exists bingo_message_reactions (
  message_id uuid not null references bingo_messages(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  reaction text not null,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

-- Receipts ------------------------------------------------------------
create table if not exists bingo_message_receipts (
  message_id uuid not null references bingo_messages(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  delivered_at timestamptz,
  read_at timestamptz,
  primary key (message_id, user_id)
);

-- Per-user message state ("delete for me") -----------------------------
create table if not exists bingo_message_user_state (
  message_id uuid not null references bingo_messages(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  deleted_for_me_at timestamptz,
  primary key (message_id, user_id)
);

-- Blocks ------------------------------------------------------------------
create table if not exists bingo_blocks (
  blocker_id uuid not null references auth.users(id),
  blocked_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);

-- Call sessions -----------------------------------------------------------
create table if not exists bingo_call_sessions (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references bingo_conversations(id) on delete cascade,
  caller_id uuid not null references auth.users(id),
  type text not null check (type in ('voice','video')),
  status text not null check (status in ('initiating','ringing','connected','declined','missed','ended','failed')),
  started_at timestamptz not null default now(),
  answered_at timestamptz,
  ended_at timestamptz
);

-- Message reports (links to existing moderation system - see note below) --
create table if not exists bingo_message_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id),
  message_id uuid references bingo_messages(id),
  conversation_id uuid references bingo_conversations(id),
  reason text not null,
  details text,
  case_id uuid, -- expected to reference bingo_moderation_cases(id); left as a plain column
                -- rather than a hard FK until Track B confirms bingo_moderation_cases'
                -- actual PK type live (Packet M1 read the table's RLS/columns from the
                -- one migration file that defines it but did not verify against a live DB)
  created_at timestamptz not null default now()
);

-- Drafts --------------------------------------------------------------------
create table if not exists bingo_message_drafts (
  user_id uuid not null references auth.users(id),
  conversation_id uuid not null references bingo_conversations(id) on delete cascade,
  body text,
  attachment_draft jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id, conversation_id)
);

-- ============================================================
-- Row Level Security — enabled on every new table. Policies drafted to the
-- minimum required for Packet M3 (Inbox/Conversation) to function; calling,
-- groups-admin, and moderation-linked policies are extended in later
-- migration drafts as those packets are implemented, not created speculatively
-- here.
-- ============================================================
alter table bingo_conversations enable row level security;
alter table bingo_conversation_participants enable row level security;
alter table bingo_messages enable row level security;
alter table bingo_message_attachments enable row level security;
alter table bingo_message_reactions enable row level security;
alter table bingo_message_receipts enable row level security;
alter table bingo_message_user_state enable row level security;
alter table bingo_blocks enable row level security;
alter table bingo_call_sessions enable row level security;
alter table bingo_message_reports enable row level security;
alter table bingo_message_drafts enable row level security;

-- A participant may read a conversation only if they are a member of it.
create policy if not exists bingo_conversations_select on bingo_conversations
  for select using (
    exists (select 1 from bingo_conversation_participants p
            where p.conversation_id = id and p.user_id = auth.uid())
  );

create policy if not exists bingo_participants_select on bingo_conversation_participants
  for select using (
    exists (select 1 from bingo_conversation_participants p2
            where p2.conversation_id = conversation_id and p2.user_id = auth.uid())
  );

-- A user may only update their OWN participant row (read/mute/archive/pin/trash state).
create policy if not exists bingo_participants_update_own on bingo_conversation_participants
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Messages: only conversation participants may read; sender_id must be auth.uid() on insert.
create policy if not exists bingo_messages_select on bingo_messages
  for select using (
    exists (select 1 from bingo_conversation_participants p
            where p.conversation_id = bingo_messages.conversation_id and p.user_id = auth.uid())
  );
create policy if not exists bingo_messages_insert on bingo_messages
  for insert with check (
    sender_id = auth.uid()
    and exists (select 1 from bingo_conversation_participants p
                where p.conversation_id = bingo_messages.conversation_id and p.user_id = auth.uid())
    -- Block check: sender must not be blocked by any other participant, and must not
    -- have blocked them either, before a message can be inserted.
    and not exists (
      select 1 from bingo_conversation_participants other
      join bingo_blocks b on
        (b.blocker_id = other.user_id and b.blocked_id = auth.uid())
        or (b.blocker_id = auth.uid() and b.blocked_id = other.user_id)
      where other.conversation_id = bingo_messages.conversation_id and other.user_id <> auth.uid()
    )
  );
-- Unsend: only the sender may set unsent_at, and only via update (never delete the row,
-- so "unsent" state is preserved and can render as a retraction placeholder).
create policy if not exists bingo_messages_update_unsend on bingo_messages
  for update using (sender_id = auth.uid()) with check (sender_id = auth.uid());

create policy if not exists bingo_reactions_select on bingo_message_reactions
  for select using (
    exists (select 1 from bingo_messages m
            join bingo_conversation_participants p on p.conversation_id = m.conversation_id
            where m.id = message_id and p.user_id = auth.uid())
  );
create policy if not exists bingo_reactions_write_own on bingo_message_reactions
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy if not exists bingo_receipts_select on bingo_message_receipts
  for select using (
    exists (select 1 from bingo_messages m
            join bingo_conversation_participants p on p.conversation_id = m.conversation_id
            where m.id = message_id and p.user_id = auth.uid())
  );
create policy if not exists bingo_receipts_write_own on bingo_message_receipts
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy if not exists bingo_user_state_own on bingo_message_user_state
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy if not exists bingo_blocks_own on bingo_blocks
  for all using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());
-- A user may also read whether THEY are blocked by someone (needed to hide
-- call/message affordances client-side; the write-side enforcement above
-- via bingo_messages_insert is the actual security boundary, not this read).
create policy if not exists bingo_blocks_select_as_blocked on bingo_blocks
  for select using (blocked_id = auth.uid() or blocker_id = auth.uid());

create policy if not exists bingo_call_sessions_select on bingo_call_sessions
  for select using (
    exists (select 1 from bingo_conversation_participants p
            where p.conversation_id = bingo_call_sessions.conversation_id and p.user_id = auth.uid())
  );
create policy if not exists bingo_call_sessions_insert on bingo_call_sessions
  for insert with check (
    caller_id = auth.uid()
    and exists (select 1 from bingo_conversation_participants p
                where p.conversation_id = bingo_call_sessions.conversation_id and p.user_id = auth.uid())
    and not exists (
      select 1 from bingo_conversation_participants other
      join bingo_blocks b on
        (b.blocker_id = other.user_id and b.blocked_id = auth.uid())
        or (b.blocker_id = auth.uid() and b.blocked_id = other.user_id)
      where other.conversation_id = bingo_call_sessions.conversation_id and other.user_id <> auth.uid()
    )
  );

create policy if not exists bingo_reports_insert_own on bingo_message_reports
  for insert with check (reporter_id = auth.uid());
-- Reports are not readable by ordinary users (moderation-only); no select
-- policy is created here, matching the existing bingo_moderation_cases
-- pattern found in Packet M1 (admin/agent read access is a separate,
-- narrowly role-checked policy to be added when this table is wired into
-- that existing moderation system, not duplicated speculatively here).

create policy if not exists bingo_drafts_own on bingo_message_drafts
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ============================================================
-- NOT INCLUDED IN THIS DRAFT (deliberately, per Packet M1 findings):
--  - Storage bucket + storage policies for message_attachments (Packet M5)
--  - A real link from bingo_message_reports.case_id into the existing
--    bingo_moderation_cases table (needs live-schema confirmation first)
--  - Group-specific admin/permission policies beyond basic participant role
--    (Packet M6)
--  - A scheduled purge job for 30-day Trash (purge_after) - per Packet M1,
--    the existing vehicle-listing trash pattern has NO server-side
--    scheduled purge either; this must be a real `pg_cron` job or Edge
--    Function, not a client-triggered purge repeating that known weakness
-- ============================================================

-- ============================================================
-- ADDITIVE, STILL DRAFT ONLY — NOT APPLIED (Phase 5 calling):
-- the real call code in BINGO_MASTER_CURRENT_VERIFIED.html best-effort
-- mirrors call session status to this table (insert on call start,
-- update on connect/end), wrapped in try/catch exactly like every other
-- Supabase write in this messaging system so it is a no-op today. No
-- policy above allowed UPDATE on bingo_call_sessions at all, so once this
-- migration is applied that mirror write would still be silently denied
-- by RLS without this policy. Ad-hoc "call link" sessions (created via
-- Create Call Link, joined by whoever opens the link) are deliberately
-- NOT written to this table at all - they have no caller/participant
-- relationship to check against, so persisting them here would need a
-- new, differently-shaped table and RLS model, not a bolt-on to this one.
-- They exist purely as ephemeral Supabase Realtime broadcast topics keyed
-- by a random token, which is why they need no schema at all.
-- ============================================================
create policy if not exists bingo_call_sessions_update_own on bingo_call_sessions
  for update using (caller_id = auth.uid())
  with check (caller_id = auth.uid());
