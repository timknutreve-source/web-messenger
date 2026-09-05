-- Direct (1:1) conversations. A conversation's two participants are also
-- recorded directly on the conversation as an ordered pair
-- (direct_user_a_id < direct_user_b_id), which lets a single partial unique
-- index guarantee "at most one direct conversation per unordered pair of
-- users" at the database level, without needing to reason about ordering
-- across two separate participant rows.
CREATE TABLE conversations (
    id                UUID PRIMARY KEY,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_activity_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    direct_user_a_id  UUID REFERENCES users(id) ON DELETE CASCADE,
    direct_user_b_id  UUID REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT conversations_direct_pair_ordered CHECK (
        direct_user_a_id IS NULL
        OR direct_user_b_id IS NULL
        OR direct_user_a_id < direct_user_b_id
    )
);

-- Enforces "exactly one direct conversation per unordered pair of users".
-- Only applies while both columns are set (future non-direct/group
-- conversations, if ever added, would leave these null and fall outside it).
CREATE UNIQUE INDEX conversations_direct_pair_unique_idx
    ON conversations (direct_user_a_id, direct_user_b_id)
    WHERE direct_user_a_id IS NOT NULL AND direct_user_b_id IS NOT NULL;

-- One row per (conversation, user). Archive state lives here rather than on
-- Conversation because it is per-user: Alice archiving a chat with Bob must
-- not affect Bob's copy of the same conversation.
CREATE TABLE conversation_participants (
    id               UUID PRIMARY KEY,
    conversation_id  UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    archived         BOOLEAN NOT NULL DEFAULT FALSE,
    archived_at      TIMESTAMPTZ,
    joined_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Prevents duplicate participant membership for the same user in the same
-- conversation.
CREATE UNIQUE INDEX conversation_participants_conversation_user_unique_idx
    ON conversation_participants (conversation_id, user_id);

-- Supports the chat-list query: "this user's non-archived (or archived)
-- conversations".
CREATE INDEX conversation_participants_user_archived_idx
    ON conversation_participants (user_id, archived);

-- Backfill: Phase 5 contacts created before this migration existed have no
-- conversation yet. `contacts` stores one directed row per side of an
-- accepted relationship (A->B and B->A), so grouping by the unordered pair
-- collapses that back down to a single conversation per pair. Idempotent
-- (guarded by NOT EXISTS), safe to reason about even if re-run.
INSERT INTO conversations (id, created_at, last_activity_at, direct_user_a_id, direct_user_b_id)
SELECT gen_random_uuid(), now(), now(), pair.user_low, pair.user_high
FROM (
    SELECT DISTINCT LEAST(c.user_id, c.contact_id) AS user_low, GREATEST(c.user_id, c.contact_id) AS user_high
    FROM contacts c
) pair
WHERE NOT EXISTS (
    SELECT 1 FROM conversations conv
    WHERE conv.direct_user_a_id = pair.user_low AND conv.direct_user_b_id = pair.user_high
);

-- Backfill participant rows for every conversation (newly backfilled or
-- otherwise) that is missing one or both of its two participants.
INSERT INTO conversation_participants (id, conversation_id, user_id, archived, joined_at)
SELECT gen_random_uuid(), conv.id, member.user_id, FALSE, now()
FROM conversations conv
CROSS JOIN LATERAL (VALUES (conv.direct_user_a_id), (conv.direct_user_b_id)) AS member(user_id)
WHERE conv.direct_user_a_id IS NOT NULL
  AND conv.direct_user_b_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM conversation_participants cp
      WHERE cp.conversation_id = conv.id AND cp.user_id = member.user_id
  );
