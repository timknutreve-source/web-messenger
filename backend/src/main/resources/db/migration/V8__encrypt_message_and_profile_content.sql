-- Phase 9 (encryption): the columns below now hold an AES-256-GCM envelope
-- (version byte + nonce + ciphertext + auth tag, Base64-encoded) rather than
-- plaintext - see EncryptionService/EncryptedStringConverter. An encrypted
-- value is always longer than its plaintext (nonce + tag + Base64 overhead),
-- so each column is widened to TEXT (Postgres has no extra storage cost for
-- TEXT vs VARCHAR(n) - both use the same underlying type). No data is
-- rewritten here: rows written before this phase still hold plaintext in
-- these columns; LegacyPlaintextMigrationRunner encrypts any such row the
-- first time the application starts against this schema (see its Javadoc
-- for why a one-time app-level pass is used instead of a SQL data
-- migration - the encryption key is only available to the application, not
-- to Flyway).
ALTER TABLE messages ALTER COLUMN content TYPE TEXT;
ALTER TABLE users ALTER COLUMN about_me TYPE TEXT;
ALTER TABLE message_attachments ALTER COLUMN original_filename TYPE TEXT;
