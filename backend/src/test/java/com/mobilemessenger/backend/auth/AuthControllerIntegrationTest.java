package com.mobilemessenger.backend.auth;

import static org.hamcrest.Matchers.notNullValue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.json.JsonMapper;

/**
 * End-to-end tests for the auth API against a real database. Each test runs
 * in its own transaction that is rolled back afterwards, so tests never leak
 * data into one another or require manual cleanup.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class AuthControllerIntegrationTest {

    private static final String STRONG_PASSWORD = "Str0ng!Pass";

    @Autowired
    private MockMvc mockMvc;

    private final JsonMapper jsonMapper = JsonMapper.builder().build();

    @Test
    void healthEndpointIsPubliclyAccessible() throws Exception {
        mockMvc.perform(get("/api/health"))
                .andExpect(status().isOk());
    }

    @Test
    void registerSucceedsWithValidInput() throws Exception {
        mockMvc.perform(registerRequest("alice", "alice@example.com", STRONG_PASSWORD))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.token", notNullValue()))
                .andExpect(jsonPath("$.user.username").value("alice"))
                .andExpect(jsonPath("$.user.email").value("alice@example.com"))
                .andExpect(jsonPath("$.user.emailVerified").value(false))
                .andExpect(jsonPath("$.user.passwordHash").doesNotExist());
    }

    @Test
    void registerRejectsDuplicateEmail() throws Exception {
        mockMvc.perform(registerRequest("alice", "alice@example.com", STRONG_PASSWORD))
                .andExpect(status().isCreated());

        mockMvc.perform(registerRequest("someoneElse", "Alice@Example.com", STRONG_PASSWORD))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error").value("Email is already registered"));
    }

    @Test
    void registerRejectsDuplicateUsername() throws Exception {
        mockMvc.perform(registerRequest("alice", "alice@example.com", STRONG_PASSWORD))
                .andExpect(status().isCreated());

        mockMvc.perform(registerRequest("ALICE", "alice2@example.com", STRONG_PASSWORD))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error").value("Username is already taken"));
    }

    @Test
    void registerRejectsInvalidEmail() throws Exception {
        mockMvc.perform(registerRequest("bob", "not-an-email", STRONG_PASSWORD))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.fieldErrors.email", notNullValue()));
    }

    @Test
    void registerRejectsWeakPassword() throws Exception {
        mockMvc.perform(registerRequest("bob", "bob@example.com", "weak"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.fieldErrors.password", notNullValue()));
    }

    @Test
    void loginSucceedsWithCorrectCredentials() throws Exception {
        mockMvc.perform(registerRequest("carol", "carol@example.com", STRONG_PASSWORD))
                .andExpect(status().isCreated());

        mockMvc.perform(loginRequest("carol", STRONG_PASSWORD))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.token", notNullValue()))
                .andExpect(jsonPath("$.user.username").value("carol"));
    }

    @Test
    void loginRejectsWrongPassword() throws Exception {
        mockMvc.perform(registerRequest("dave", "dave@example.com", STRONG_PASSWORD))
                .andExpect(status().isCreated());

        mockMvc.perform(loginRequest("dave", "WrongPassword1!"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.error").value("Invalid credentials"));
    }

    @Test
    void loginRejectsUnknownUser() throws Exception {
        mockMvc.perform(loginRequest("ghost", "WhoKnows1!"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.error").value("Invalid credentials"));
    }

    @Test
    void meRequiresAuthentication() throws Exception {
        mockMvc.perform(get("/api/auth/me"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void meReturnsCurrentUserWhenAuthenticated() throws Exception {
        MvcResult registerResult = mockMvc.perform(registerRequest("erin", "erin@example.com", STRONG_PASSWORD))
                .andExpect(status().isCreated())
                .andReturn();

        String token = extractToken(registerResult);

        mockMvc.perform(get("/api/auth/me").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.username").value("erin"))
                .andExpect(jsonPath("$.email").value("erin@example.com"))
                .andExpect(jsonPath("$.passwordHash").doesNotExist());
    }

    private org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder registerRequest(
            String username, String email, String password) throws Exception {
        String body = jsonMapper.writeValueAsString(new RegisterPayload(username, email, password));
        return post("/api/auth/register").contentType(MediaType.APPLICATION_JSON).content(body);
    }

    private org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder loginRequest(
            String usernameOrEmail, String password) throws Exception {
        String body = jsonMapper.writeValueAsString(new LoginPayload(usernameOrEmail, password));
        return post("/api/auth/login").contentType(MediaType.APPLICATION_JSON).content(body);
    }

    private String extractToken(MvcResult result) throws Exception {
        var node = jsonMapper.readTree(result.getResponse().getContentAsString());
        return node.get("token").asString();
    }

    private record RegisterPayload(String username, String email, String password) {
    }

    private record LoginPayload(String usernameOrEmail, String password) {
    }
}
