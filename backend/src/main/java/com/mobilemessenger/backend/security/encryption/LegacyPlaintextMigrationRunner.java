package com.mobilemessenger.backend.security.encryption;

import com.mobilemessenger.backend.security.encryption.exception.DecryptionException;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/**
 * One-time, idempotent, startup-time encryption of any pre-existing
 * plaintext left over from before Phase 9 in the columns that {@link
 * EncryptedStringConverter} now protects.
 *
 * <p>V8__encrypt_message_and_profile_content.sql only widens the affected
 * columns (VARCHAR -> TEXT) so an encrypted envelope fits; it deliberately
 * does not rewrite any data, because encrypting requires the master key,
 * which only the running application has access to - a plain SQL migration
 * cannot call {@link EncryptionService}. Instead, this runs once per
 * startup (cheap and safe to repeat): for each row whose value doesn't
 * already look like a valid envelope, it encrypts the value in place via a
 * direct {@code UPDATE} (bypassing the entity layer, since going through
 * JPA would re-trigger the same converter and double-encrypt nothing - it's
 * simplest to reason about as a plain SQL update).
 *
 * <p>"Doesn't already look like a valid envelope" is determined by trying
 * to decrypt it: legitimate legacy plaintext will not parse as a
 * version-1/nonce/GCM-tag envelope and fails with {@link
 * DecryptionException}, while an already-encrypted value decrypts
 * successfully and is left untouched (forging a value that both looks like
 * plaintext someone typed AND happens to pass GCM tag authentication is
 * cryptographically negligible). A row is never deleted or blanked - if
 * encryption of a single row unexpectedly fails, that row is logged and
 * skipped rather than aborting startup or the rest of the pass.
 */
@Component
@Order(Integer.MAX_VALUE)
public class LegacyPlaintextMigrationRunner implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(LegacyPlaintextMigrationRunner.class);

    private final JdbcTemplate jdbcTemplate;
    private final EncryptionService encryptionService;

    public LegacyPlaintextMigrationRunner(JdbcTemplate jdbcTemplate, EncryptionService encryptionService) {
        this.jdbcTemplate = jdbcTemplate;
        this.encryptionService = encryptionService;
    }

    @Override
    public void run(ApplicationArguments args) {
        migrate("messages", "id", "content");
        migrate("users", "id", "about_me");
        migrate("message_attachments", "id", "original_filename");
    }

    private void migrate(String table, String idColumn, String valueColumn) {
        List<Map<String, Object>> rows = jdbcTemplate.queryForList(
                "SELECT " + idColumn + " AS row_id, " + valueColumn + " AS row_value FROM " + table
                        + " WHERE " + valueColumn + " IS NOT NULL");

        int migrated = 0;
        for (Map<String, Object> row : rows) {
            String value = (String) row.get("row_value");
            if (alreadyEncrypted(value)) {
                continue;
            }
            UUID id = (UUID) row.get("row_id");
            try {
                String encrypted = encryptionService.encrypt(value);
                jdbcTemplate.update(
                        "UPDATE " + table + " SET " + valueColumn + " = ? WHERE " + idColumn + " = ?", encrypted, id);
                migrated++;
            } catch (Exception e) {
                // Never log the plaintext value itself.
                log.warn(
                        "Could not encrypt pre-existing plaintext in {}.{} for row {}: {}",
                        table,
                        valueColumn,
                        id,
                        e.getClass().getSimpleName());
            }
        }
        if (migrated > 0) {
            log.info("Encrypted {} pre-existing plaintext row(s) in {}.{}", migrated, table, valueColumn);
        }
    }

    private boolean alreadyEncrypted(String value) {
        try {
            encryptionService.decrypt(value);
            return true;
        } catch (DecryptionException e) {
            return false;
        }
    }
}
