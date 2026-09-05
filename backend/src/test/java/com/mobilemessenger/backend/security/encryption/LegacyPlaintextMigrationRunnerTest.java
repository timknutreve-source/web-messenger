package com.mobilemessenger.backend.security.encryption;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.json.JsonMapper;

/**
 * Proves the one-time migration path for data written before Phase 9: a raw
 * plaintext value already sitting in a protected column (simulating a row
 * from before encryption existed) gets encrypted in place the next time
 * {@link LegacyPlaintextMigrationRunner} runs, without ever being touched
 * more than once (idempotent) and without disturbing rows that are already
 * encrypted.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class LegacyPlaintextMigrationRunnerTest {

    private static final String STRONG_PASSWORD = "Str0ng!Pass";
    private static final String LEGACY_MARKER = "LEGACY_PLAINTEXT_ABOUT_ME_MARKER";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private EncryptionService encryptionService;

    @Autowired
    private LegacyPlaintextMigrationRunner migrationRunner;

    @Autowired
    private jakarta.persistence.EntityManager entityManager;

    private final JsonMapper jsonMapper = JsonMapper.builder().build();

    @Test
    void encryptsPreExistingPlaintextAboutMeInPlace() throws Exception {
        RegisteredUser alice = register("alice_legacy_migrate", "alice.legacy.migrate@example.com");
        entityManager.flush();

        // Simulate a row written before encryption existed: write plaintext
        // directly via JDBC, bypassing the entity layer / converter entirely.
        jdbcTemplate.update("UPDATE users SET about_me = ? WHERE id = ?", LEGACY_MARKER, alice.id);

        migrationRunner.run(null);

        String rawColumnValue =
                jdbcTemplate.queryForObject("SELECT about_me FROM users WHERE id = ?", String.class, alice.id);
        assertFalse(rawColumnValue.contains(LEGACY_MARKER), "legacy plaintext was not encrypted in place");
        assertEquals(LEGACY_MARKER, encryptionService.decrypt(rawColumnValue));
    }

    @Test
    void runningTwiceDoesNotDoubleEncryptOrCorruptTheValue() throws Exception {
        RegisteredUser alice = register("alice_legacy_twice", "alice.legacy.twice@example.com");
        entityManager.flush();
        jdbcTemplate.update("UPDATE users SET about_me = ? WHERE id = ?", LEGACY_MARKER, alice.id);

        migrationRunner.run(null);
        String afterFirstRun =
                jdbcTemplate.queryForObject("SELECT about_me FROM users WHERE id = ?", String.class, alice.id);

        migrationRunner.run(null);
        String afterSecondRun =
                jdbcTemplate.queryForObject("SELECT about_me FROM users WHERE id = ?", String.class, alice.id);

        assertEquals(afterFirstRun, afterSecondRun, "an already-encrypted value should be left untouched");
        assertEquals(LEGACY_MARKER, encryptionService.decrypt(afterSecondRun));
    }

    @Test
    void alreadyEncryptedRowsAreLeftAlone() throws Exception {
        RegisteredUser alice = register("alice_legacy_already", "alice.legacy.already@example.com");

        String properlyEncryptedMarker = "PROPERLY_ENCRYPTED_MARKER";
        mockMvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put("/api/profile")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(jsonMapper.writeValueAsString(new UpdateProfilePayload(
                                "alice_legacy_already", "alice.legacy.already@example.com", properlyEncryptedMarker)))
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isOk());
        entityManager.flush();

        String beforeMigration =
                jdbcTemplate.queryForObject("SELECT about_me FROM users WHERE id = ?", String.class, alice.id);

        migrationRunner.run(null);

        String afterMigration =
                jdbcTemplate.queryForObject("SELECT about_me FROM users WHERE id = ?", String.class, alice.id);
        assertEquals(beforeMigration, afterMigration, "an already-encrypted row must not be re-encrypted");
    }

    @Test
    void encryptsPreExistingPlaintextMessageContentInPlace() throws Exception {
        RegisteredUser alice = register("alice_legacy_msg", "alice.legacy.msg@example.com");
        RegisteredUser bob = register("bob_legacy_msg", "bob.legacy.msg@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        entityManager.flush();

        // Insert a message row directly, as if it had been written before
        // encryption existed.
        UUID messageId = UUID.randomUUID();
        jdbcTemplate.update(
                "INSERT INTO messages (id, conversation_id, sender_id, content, status, created_at) "
                        + "VALUES (?, ?, ?, ?, 'SENT', ?)",
                messageId,
                chatId,
                alice.id,
                LEGACY_MARKER,
                java.sql.Timestamp.from(Instant.now()));

        migrationRunner.run(null);

        String rawColumnValue =
                jdbcTemplate.queryForObject("SELECT content FROM messages WHERE id = ?", String.class, messageId);
        assertFalse(rawColumnValue.contains(LEGACY_MARKER));
        assertEquals(LEGACY_MARKER, encryptionService.decrypt(rawColumnValue));
    }

    // ---- helpers ----

    private UUID becomeContactsAndGetChatId(RegisteredUser sender, RegisteredUser recipient) throws Exception {
        String body = jsonMapper.writeValueAsString(new SendInvitationPayload(recipient.id));
        MvcResult invResult = mockMvc.perform(post("/api/contacts/invitations")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body)
                        .header("Authorization", "Bearer " + sender.token))
                .andExpect(status().isCreated())
                .andReturn();
        UUID invitationId = UUID.fromString(
                jsonMapper.readTree(invResult.getResponse().getContentAsString()).get("id").asString());

        mockMvc.perform(post("/api/contacts/invitations/" + invitationId + "/accept")
                        .header("Authorization", "Bearer " + recipient.token))
                .andExpect(status().isOk());

        MvcResult chatsResult = mockMvc.perform(
                        org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get("/api/chats")
                                .header("Authorization", "Bearer " + sender.token))
                .andExpect(status().isOk())
                .andReturn();
        var node = jsonMapper.readTree(chatsResult.getResponse().getContentAsString());
        return UUID.fromString(node.get(0).get("id").asString());
    }

    private RegisteredUser register(String username, String email) throws Exception {
        String body = jsonMapper.writeValueAsString(new RegisterPayload(username, email, STRONG_PASSWORD));
        MvcResult result = mockMvc.perform(
                        post("/api/auth/register").contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isCreated())
                .andReturn();
        var node = jsonMapper.readTree(result.getResponse().getContentAsString());
        String token = node.get("token").asString();
        UUID id = UUID.fromString(node.get("user").get("id").asString());
        return new RegisteredUser(id, token);
    }

    private record RegisteredUser(UUID id, String token) {
    }

    private record RegisterPayload(String username, String email, String password) {
    }

    private record SendInvitationPayload(UUID recipientId) {
    }

    private record UpdateProfilePayload(String username, String email, String aboutMe) {
    }
}
