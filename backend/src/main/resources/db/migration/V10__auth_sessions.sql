-- One row per signed-in device/browser. Every JWT carries its session's id
-- (the "sid" claim), so signing out on one device revokes only that session
-- and never touches the same account's sessions on other devices - which is
-- what makes "logged in on mobile and web at the same time" and "logging out
-- of one must not log out the other" true server-side, rather than only a
-- side effect of each client forgetting its own token.
CREATE TABLE auth_sessions (
    id            UUID PRIMARY KEY,
    user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_label  VARCHAR(100) NOT NULL DEFAULT 'Unknown device',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at    TIMESTAMPTZ
);

CREATE INDEX auth_sessions_user_idx ON auth_sessions (user_id);
