CREATE TABLE users (
    id              UUID PRIMARY KEY,
    username        VARCHAR(30) NOT NULL,
    email           VARCHAR(255) NOT NULL,
    password_hash   VARCHAR(255) NOT NULL,
    email_verified  BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX users_email_unique_idx ON users (email);
CREATE UNIQUE INDEX users_username_unique_idx ON users (LOWER(username));
