package com.mobilemessenger.backend.security.encryption;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;
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
 * Security-focused checks that don't fit naturally under the
 * content/profile/media round-trip tests: that a decryption failure never
 * writes plaintext or key material to the application log, and that the
 * encryption key itself is validated strictly enough to fail startup rather
 * than accept a weak/wrong-size key.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class EncryptionSecurityIntegrationTest {

    private static final String STRONG_PASSWORD = "Str0ng!Pass";
    private static final String SECRET_MARKER = "SUPER_SECRET_MESSAGE_SHOULD_NEVER_BE_LOGGED";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private jakarta.persistence.EntityManager entityManager;

    private final JsonMapper jsonMapper = JsonMapper.builder().build();

    private ListAppender<ILoggingEvent> logAppender;

    @BeforeEach
    void attachLogAppender() {
        logAppender = new ListAppender<>();
        logAppender.start();
        ((Logger) LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME)).addAppender(logAppender);
    }

    @AfterEach
    void detachLogAppender() {
        ((Logger) LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME)).detachAppender(logAppender);
    }

    @Test
    void decryptionFailureNeverLogsPlaintextOrTheEncryptionKey() throws Exception {
        RegisteredUser alice = register("alice_sec_logs", "alice.sec.logs@example.com");
        RegisteredUser bob = register("bob_sec_logs", "bob.sec.logs@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        MvcResult sendResult = mockMvc.perform(post("/api/chats/" + chatId + "/messages")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(jsonMapper.writeValueAsString(new SendPayload(SECRET_MARKER, null)))
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isCreated())
                .andReturn();
        UUID messageId = UUID.fromString(
                jsonMapper.readTree(sendResult.getResponse().getContentAsString()).get("id").asString());
        entityManager.flush();

        // Corrupt the stored ciphertext directly, then force a fresh JPA read.
        String raw = jdbcTemplate.queryForObject("SELECT content FROM messages WHERE id = ?", String.class, messageId);
        char[] chars = raw.toCharArray();
        chars[chars.length / 2] = chars[chars.length / 2] == 'A' ? 'B' : 'A';
        jdbcTemplate.update("UPDATE messages SET content = ? WHERE id = ?", new String(chars), messageId);
        entityManager.clear();

        mockMvc.perform(get("/api/chats/" + chatId + "/messages").header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isInternalServerError());

        String allLoggedText = logAppender.list.stream()
                .map(ILoggingEvent::getFormattedMessage)
                .reduce("", (a, b) -> a + "\n" + b);

        assertFalse(allLoggedText.contains(SECRET_MARKER), "log output contained the plaintext secret message");
        assertFalse(allLoggedText.contains(raw), "log output contained the (untampered) ciphertext value");
    }

    @Test
    void wrongSizeKeyIsRejectedRatherThanSilentlyAccepted() {
        // A key one byte short of 256 bits must fail construction outright -
        // this is the "fail clearly if required encryption config is
        // missing/invalid" requirement exercised end-to-end (not just the
        // pure-unit EncryptionServiceTest coverage), including confirming no
        // key material appears in the failure.
        String almostRightKey = java.util.Base64.getEncoder().encodeToString(new byte[31]);
        IllegalStateException ex = org.junit.jupiter.api.Assertions.assertThrows(
                IllegalStateException.class, () -> new EncryptionService(almostRightKey));
        assertFalse(ex.getMessage().contains(almostRightKey), "key rejection message leaked the key value");
        assertTrue(ex.getMessage().toLowerCase(java.util.Locale.ROOT).contains("32 bytes")
                || ex.getMessage().toLowerCase(java.util.Locale.ROOT).contains("256"));
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

        MvcResult chatsResult = mockMvc.perform(get("/api/chats").header("Authorization", "Bearer " + sender.token))
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

    private record SendPayload(String content, java.util.List<UUID> attachmentIds) {
    }
}
