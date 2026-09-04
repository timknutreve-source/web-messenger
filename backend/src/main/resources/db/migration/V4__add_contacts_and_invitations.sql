CREATE TABLE contact_invitations (
    id           UUID PRIMARY KEY,
    sender_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    recipient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status       VARCHAR(20) NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    responded_at TIMESTAMPTZ,
    CONSTRAINT contact_invitations_no_self_invite CHECK (sender_id <> recipient_id)
);

CREATE INDEX contact_invitations_recipient_status_idx ON contact_invitations (recipient_id, status);
CREATE INDEX contact_invitations_sender_idx ON contact_invitations (sender_id);

-- At most one PENDING invitation per sender->recipient pair at a time. A
-- prior ACCEPTED/DECLINED invitation between the same two users doesn't
-- block a new one (e.g. re-inviting after a decline).
CREATE UNIQUE INDEX contact_invitations_pending_unique_idx
    ON contact_invitations (sender_id, recipient_id)
    WHERE status = 'PENDING';

-- One directed row per side of an accepted relationship (see Contact.java) -
-- an accepted invitation between A and B produces both (A, B) and (B, A),
-- so "list my contacts" is a single indexed lookup by user_id.
CREATE TABLE contacts (
    id         UUID PRIMARY KEY,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    contact_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT contacts_no_self_contact CHECK (user_id <> contact_id)
);

CREATE UNIQUE INDEX contacts_user_contact_unique_idx ON contacts (user_id, contact_id);
CREATE INDEX contacts_user_id_idx ON contacts (user_id);
