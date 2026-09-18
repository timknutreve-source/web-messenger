package com.mobilemessenger.backend.security.encryption;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.Map;
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
import com.mobilemessenger.backend.user.UserRepository;
import tools.jackson.databind.json.JsonMapper;

/**
 * Proves the core Phase 9 requirement for message content: a direct SQL
 * query against the {@code messages} table never reveals plaintext message
 * text, while the API keeps returning the original text to authorized
 * participants. Uses a raw {@link JdbcTemplate} query (bypassing JPA/the
 * entity layer entirely) so the check can't be fooled by
 * {@code EncryptedStringConverter} transparently decrypting on read - this
 * queries exactly what PostgreSQL actually stores.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class MessageContentEncryptionIntegrationTest {

    private static final String STRONG_PASSWORD = "Str0ng!Pass";
    private static final String MARKER = "THIS_IS_SECRET_MESSAGE_123456";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private EncryptionService encryptionService;

    @Autowired
    private jakarta.persistence.EntityManager entityManager;

    @Autowired
    private UserRepository userRepository;

    private final JsonMapper jsonMapper = JsonMapper.builder().build();

    @Test
    void messageContentIsNeverStoredAsPlaintextInThePostgresColumn() throws Exception {
        RegisteredUser alice = register("alice_enc_msg", "alice.enc.msg@example.com");
        RegisteredUser bob = register("bob_enc_msg", "bob.enc.msg@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        MvcResult sendResult = mockMvc.perform(post("/api/chats/" + chatId + "/messages")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(jsonMapper.writeValueAsString(new SendPayload(MARKER, null)))
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.content").value(MARKER))
                .andReturn();
        UUID messageId = UUID.fromString(
                jsonMapper.readTree(sendResult.getResponse().getContentAsString()).get("id").asString());

        // Direct SQL, not JPA: this is exactly what someone inspecting the
        // database with psql would see.
        Map<String, Object> row = jdbcTemplate.queryForMap(
                "SELECT content FROM messages WHERE id = ?", messageId);
        String rawColumnValue = (String) row.get("content");

        assertNotNull(rawColumnValue);
        assertFalse(rawColumnValue.contains(MARKER), "raw database column contained the plaintext marker");
        assertFalse(rawColumnValue.isEmpty());

        // But it decrypts back to exactly the original text.
        assertEquals(MARKER, encryptionService.decrypt(rawColumnValue));

        // And the recipient still sees the original plaintext through the API.
        mockMvc.perform(get("/api/chats/" + chatId + "/messages").header("Authorization", "Bearer " + bob.token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.messages[0].content").value(MARKER));
    }

    @Test
    void editedMessageContentIsAlsoNeverStoredAsPlaintext() throws Exception {
        RegisteredUser alice = register("alice_enc_edit", "alice.enc.edit@example.com");
        RegisteredUser bob = register("bob_enc_edit", "bob.enc.edit@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        MvcResult sendResult = mockMvc.perform(post("/api/chats/" + chatId + "/messages")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(jsonMapper.writeValueAsString(new SendPayload("original text", null)))
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isCreated())
                .andReturn();
        UUID messageId = UUID.fromString(
                jsonMapper.readTree(sendResult.getResponse().getContentAsString()).get("id").asString());

        String editedMarker = "EDITED_" + MARKER;
        mockMvc.perform(put("/api/chats/" + chatId + "/messages/" + messageId)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(jsonMapper.writeValueAsString(new SendPayload(editedMarker, null)))
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content").value(editedMarker));

        // MessageService.editMessage saves via the JPA session without an
        // explicit flush, so its UPDATE is still only pending in Hibernate's
        // persistence context at this point - a raw JDBC read on the same
        // connection/transaction would otherwise see the pre-edit row.
        entityManager.flush();

        String rawColumnValue = jdbcTemplate.queryForObject(
                "SELECT content FROM messages WHERE id = ?", String.class, messageId);
        assertFalse(rawColumnValue.contains(editedMarker));
        assertEquals(editedMarker, encryptionService.decrypt(rawColumnValue));
    }

    @Test
    void chatListPreviewComesFromDecryptedContentNotPlaintextInTheDatabase() throws Exception {
        RegisteredUser alice = register("alice_enc_prev", "alice.enc.prev@example.com");
        RegisteredUser bob = register("bob_enc_prev", "bob.enc.prev@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        mockMvc.perform(post("/api/chats/" + chatId + "/messages")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(jsonMapper.writeValueAsString(new SendPayload(MARKER, null)))
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isCreated());

        String rawColumnValue = jdbcTemplate.queryForObject(
                "SELECT content FROM messages WHERE conversation_id = ?", String.class, chatId);
        assertFalse(rawColumnValue.contains(MARKER));

        mockMvc.perform(get("/api/chats").header("Authorization", "Bearer " + bob.token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].lastMessage.content").value(MARKER));
    }

    @Test
    void tamperedMessageContentFailsSafelyInsteadOfReturningGarbage() throws Exception {
        RegisteredUser alice = register("alice_enc_tamper", "alice.enc.tamper@example.com");
        RegisteredUser bob = register("bob_enc_tamper", "bob.enc.tamper@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        MvcResult sendResult = mockMvc.perform(post("/api/chats/" + chatId + "/messages")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(jsonMapper.writeValueAsString(new SendPayload("perfectly normal message", null)))
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isCreated())
                .andReturn();
        UUID messageId = UUID.fromString(
                jsonMapper.readTree(sendResult.getResponse().getContentAsString()).get("id").asString());

        // Simulate direct tampering with the stored ciphertext (e.g. a
        // compromised database) by corrupting a middle character.
        String raw = jdbcTemplate.queryForObject("SELECT content FROM messages WHERE id = ?", String.class, messageId);
        char[] chars = raw.toCharArray();
        chars[chars.length / 2] = chars[chars.length / 2] == 'A' ? 'B' : 'A';
        jdbcTemplate.update("UPDATE messages SET content = ? WHERE id = ?", new String(chars), messageId);

        assertThrows(
                com.mobilemessenger.backend.security.encryption.exception.DecryptionException.class,
                () -> encryptionService.decrypt(new String(chars)));

        // The raw UPDATE above bypassed Hibernate entirely, so the still-managed
        // Message entity from the earlier send is now stale in the persistence
        // context (holding the untampered content). Clearing it forces the next
        // JPA read to actually re-hydrate from the row we just corrupted.
        entityManager.clear();

        mockMvc.perform(get("/api/chats/" + chatId + "/messages").header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.error").value("Unable to process encrypted data"));
    }

    // ---- helpers ----

    private UUID becomeContactsAndGetChatId(RegisteredUser sender, RegisteredUser recipient) throws Exception {
        UUID invitationId = sendInvitationAndGetId(sender.token, recipient.id);
        mockMvc.perform(post("/api/contacts/invitations/" + invitationId + "/accept")
                        .header("Authorization", "Bearer " + recipient.token))
                .andExpect(status().isOk());

        MvcResult chatsResult = mockMvc.perform(get("/api/chats").header("Authorization", "Bearer " + sender.token))
                .andExpect(status().isOk())
                .andReturn();
        var node = jsonMapper.readTree(chatsResult.getResponse().getContentAsString());
        return UUID.fromString(node.get(0).get("id").asString());
    }

    private UUID sendInvitationAndGetId(String senderToken, UUID recipientId) throws Exception {
        String body = jsonMapper.writeValueAsString(new SendInvitationPayload(recipientId));
        MvcResult result = mockMvc.perform(post("/api/contacts/invitations")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body)
                        .header("Authorization", "Bearer " + senderToken))
                .andExpect(status().isCreated())
                .andReturn();
        return UUID.fromString(
                jsonMapper.readTree(result.getResponse().getContentAsString()).get("id").asString());
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
        userRepository.findById(id).ifPresent(user -> {
            user.setEmailVerified(true);
            userRepository.save(user);
        });
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
