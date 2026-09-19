-- Polls live inside group chats. A poll is attached to an ordinary message
-- (the message's content is the question), so it appears in the timeline,
-- sorts the chat list, and is deleted/searched like any other message.
CREATE TABLE polls (
    id               UUID PRIMARY KEY,
    conversation_id  UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    message_id       UUID NOT NULL UNIQUE REFERENCES messages(id) ON DELETE CASCADE,
    created_by       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    -- Anonymous polls only ever expose totals per option, never who voted.
    anonymous        BOOLEAN NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE poll_options (
    id        UUID PRIMARY KEY,
    poll_id   UUID NOT NULL REFERENCES polls(id) ON DELETE CASCADE,
    position  INT NOT NULL,
    -- Application-level encrypted at rest, like message text.
    text      TEXT NOT NULL
);

CREATE INDEX poll_options_poll_idx ON poll_options (poll_id, position);

-- One vote per user per poll; changing a vote updates the row, retracting
-- deletes it. (Even an anonymous poll must remember who voted so a vote can
-- be changed or retracted - anonymity is about what other users can see.)
CREATE TABLE poll_votes (
    id        UUID PRIMARY KEY,
    poll_id   UUID NOT NULL REFERENCES polls(id) ON DELETE CASCADE,
    option_id UUID NOT NULL REFERENCES poll_options(id) ON DELETE CASCADE,
    user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    voted_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX poll_votes_poll_user_idx ON poll_votes (poll_id, user_id);
CREATE INDEX poll_votes_option_idx ON poll_votes (option_id);
