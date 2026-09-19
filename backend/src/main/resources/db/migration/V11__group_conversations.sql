-- Group conversations, group invitations, and per-recipient message receipts.
--
-- A conversation is now either DIRECT (the existing 1:1 chats, identified by
-- the ordered user pair on the row) or a GROUP (a named conversation whose
-- members are simply its participant rows). Existing rows are all DIRECT and
-- are left exactly as they are.
ALTER TABLE conversations ADD COLUMN type VARCHAR(10) NOT NULL DEFAULT 'DIRECT';
-- The group's name is chat-list content, so it is application-level encrypted
-- at rest like message text (hence TEXT: ciphertext is longer than plaintext).
ALTER TABLE conversations ADD COLUMN name TEXT;
ALTER TABLE conversations ADD COLUMN created_by UUID REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE conversations ADD CONSTRAINT conversations_type_shape CHECK (
    (type = 'DIRECT' AND direct_user_a_id IS NOT NULL AND direct_user_b_id IS NOT NULL)
    OR
    (type = 'GROUP' AND direct_user_a_id IS NULL AND direct_user_b_id IS NULL AND name IS NOT NULL)
);

ALTER TABLE conversation_participants ADD COLUMN role VARCHAR(10) NOT NULL DEFAULT 'MEMBER';

-- Invitations to join a group. Membership is only ever created by the invitee
-- accepting - never by the inviter adding someone unilaterally.
CREATE TABLE group_invitations (
    id               UUID PRIMARY KEY,
    conversation_id  UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    inviter_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    invitee_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status           VARCHAR(10) NOT NULL DEFAULT 'PENDING',
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    responded_at     TIMESTAMPTZ,
    CONSTRAINT group_invitations_not_self CHECK (inviter_id <> invitee_id)
);

-- At most one pending invitation per (group, invitee); a past declined one
-- never blocks inviting the same person again.
CREATE UNIQUE INDEX group_invitations_pending_unique_idx
    ON group_invitations (conversation_id, invitee_id) WHERE status = 'PENDING';
CREATE INDEX group_invitations_invitee_idx ON group_invitations (invitee_id, status);

-- Delivery/read state per (message, recipient). A direct chat keeps using the
-- single status column on the message (it has exactly one recipient); a group
-- message has many, so its status is derived from these rows: DELIVERED once
-- every recipient has received it, READ once every recipient has read it.
CREATE TABLE message_receipts (
    id            UUID PRIMARY KEY,
    message_id    UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    delivered_at  TIMESTAMPTZ,
    read_at       TIMESTAMPTZ
);

CREATE UNIQUE INDEX message_receipts_message_user_idx ON message_receipts (message_id, user_id);
CREATE INDEX message_receipts_user_read_idx ON message_receipts (user_id, read_at);
