-- Verification/reset now use a short 6-digit numeric code (emailed to the
-- user, entered directly in the app) instead of a long random token embedded
-- in a clickable link. token_hash keeps storing only a SHA-256 hash of the
-- code - never the raw code - but a 6-digit code's much smaller space makes
-- global uniqueness on the hash both no longer meaningful (lookups are now
-- scoped to a single user's pending code, see the repositories) and actually
-- likely to collide across different users, so the old unique index is
-- dropped. attempts guards the online-guessing surface that a short code
-- otherwise opens up.
DROP INDEX email_verification_tokens_token_hash_idx;
ALTER TABLE email_verification_tokens ADD COLUMN attempts INT NOT NULL DEFAULT 0;

DROP INDEX password_reset_tokens_token_hash_idx;
ALTER TABLE password_reset_tokens ADD COLUMN attempts INT NOT NULL DEFAULT 0;
