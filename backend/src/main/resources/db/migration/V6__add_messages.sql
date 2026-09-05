-- Text messages within a conversation. Status tracks the application-level
-- SENT -> DELIVERED -> READ lifecycle (never the WebSocket transport's own
-- delivery semantics). Deletion is soft: deleted_at is set and content is
-- cleared in place, so a deleted message keeps its row (position/timestamp
-- preserved) but its original text can never be re-read from the database.
CREATE TABLE messages (
    id              UUID PRIMARY KEY,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content         VARCHAR(4000) NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'SENT',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    edited_at       TIMESTAMPTZ,
    deleted_at      TIMESTAMPTZ
);

-- Supports "messages for conversation ordered by creation time" (most
-- recent page first, with created_at+id as a stable keyset-pagination
-- cursor for loading older pages).
CREATE INDEX messages_conversation_created_idx ON messages (conversation_id, created_at DESC, id DESC);

-- Supports "messages by sender".
CREATE INDEX messages_sender_idx ON messages (sender_id);

-- Supports "unread messages for recipient" (bulk mark-as-read on opening a
-- conversation: every message in the conversation not sent by the caller
-- and not already READ).
CREATE INDEX messages_conversation_status_idx ON messages (conversation_id, status);
