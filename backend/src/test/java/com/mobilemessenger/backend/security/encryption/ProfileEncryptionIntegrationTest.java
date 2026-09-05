package com.mobilemessenger.backend.security.encryption;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

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
 * Proves the core Phase 9 requirement for profile data: a direct SQL query
 * against the {@code users} table never reveals plaintext "About Me" text,
 * while the profile API keeps returning the original text to its owner -
 * and username/email uniqueness (which stay plaintext, deliberately) is
 * unaffected.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class ProfileEncryptionIntegrationTest {

    private static final String STRONG_PASSWORD = "Str0ng!Pass";
    private static final String MARKER = "THIS_IS_SECRET_ABOUT_ME_123456";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private EncryptionService encryptionService;

    @Autowired
    private jakarta.persistence.EntityManager entityManager;

    private final JsonMapper jsonMapper = JsonMapper.builder().build();

    @Test
    void aboutMeIsNeverStoredAsPlaintextInThePostgresColumn() throws Exception {
        RegisteredUser alice = register("alice_enc_profile", "alice.enc.profile@example.com");

        mockMvc.perform(put("/api/profile")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(jsonMapper.writeValueAsString(
                                new UpdateProfilePayload("alice_enc_profile", "alice.enc.profile@example.com", MARKER)))
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.aboutMe").value(MARKER));
        entityManager.flush();

        String rawColumnValue =
                jdbcTemplate.queryForObject("SELECT about_me FROM users WHERE id = ?", String.class, alice.id);

        assertNotNull(rawColumnValue);
        assertFalse(rawColumnValue.contains(MARKER), "raw database column contained the plaintext marker");
        assertEquals(MARKER, encryptionService.decrypt(rawColumnValue));

        // Reload through the API (a fresh read, not just the update response echo).
        mockMvc.perform(get("/api/profile").header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.aboutMe").value(MARKER));
    }

    @Test
    void aboutMeSurvivesAnEditAndStaysEncrypted() throws Exception {
        RegisteredUser alice = register("alice_enc_edit_pf", "alice.enc.editpf@example.com");

        mockMvc.perform(put("/api/profile")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(jsonMapper.writeValueAsString(
                                new UpdateProfilePayload("alice_enc_edit_pf", "alice.enc.editpf@example.com", "first bio")))
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isOk());

        String updatedMarker = "UPDATED_" + MARKER;
        mockMvc.perform(put("/api/profile")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(jsonMapper.writeValueAsString(
                                new UpdateProfilePayload("alice_enc_edit_pf", "alice.enc.editpf@example.com", updatedMarker)))
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.aboutMe").value(updatedMarker));
        entityManager.flush();

        String rawColumnValue =
                jdbcTemplate.queryForObject("SELECT about_me FROM users WHERE id = ?", String.class, alice.id);
        assertFalse(rawColumnValue.contains(updatedMarker));
        assertEquals(updatedMarker, encryptionService.decrypt(rawColumnValue));
    }

    @Test
    void usernameAndEmailStayPlaintextAndUniquenessStillWorks() throws Exception {
        RegisteredUser alice = register("alice_enc_unique", "alice.enc.unique@example.com");
        register("bob_enc_unique", "bob.enc.unique@example.com");

        // Username/email are deliberately not encrypted (needed for login
        // lookup and uniqueness) - direct SQL should show them in plaintext.
        String rawUsername =
                jdbcTemplate.queryForObject("SELECT username FROM users WHERE id = ?", String.class, alice.id);
        assertEquals("alice_enc_unique", rawUsername);

        // And the existing uniqueness constraint (enforced against plaintext) still works.
        mockMvc.perform(put("/api/profile")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(jsonMapper.writeValueAsString(
                                new UpdateProfilePayload("bob_enc_unique", "alice.enc.unique@example.com", null)))
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isConflict());
    }

    // ---- helpers ----

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

    private record UpdateProfilePayload(String username, String email, String aboutMe) {
    }
}
