-- Images/videos attached to messages. An attachment is uploaded before the
-- message that will carry it exists (the client uploads, gets an id back,
-- then sends the message referencing it), so message_id starts NULL
-- ("pending") and is set once a message consumes it - see MessageService.
-- conversation_id/uploader_id are recorded independently of message_id so a
-- still-pending attachment can be authorized (only its uploader may access
-- it) before it belongs to any message.
CREATE TABLE message_attachments (
    id                    UUID PRIMARY KEY,
    conversation_id       UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    message_id            UUID REFERENCES messages(id) ON DELETE CASCADE,
    uploader_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type                  VARCHAR(20) NOT NULL,
    storage_key           VARCHAR(255) NOT NULL,
    thumbnail_storage_key VARCHAR(255),
    original_filename     VARCHAR(255),
    mime_type             VARCHAR(100) NOT NULL,
    file_size             BIGINT NOT NULL,
    width                 INTEGER,
    height                INTEGER,
    duration_seconds      INTEGER,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Batch-loading attachments for a page of messages (avoids N+1 queries).
CREATE INDEX message_attachments_message_id_idx ON message_attachments (message_id);

-- Looking up a user's own not-yet-sent uploads within a conversation, e.g.
-- to authorize attaching them to the message currently being composed.
CREATE INDEX message_attachments_pending_idx
    ON message_attachments (conversation_id, uploader_id)
    WHERE message_id IS NULL;
