package com.mobilemessenger.backend.contact;

import static org.hamcrest.Matchers.hasSize;
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
import com.mobilemessenger.backend.user.UserRepository;
import java.util.UUID;
import tools.jackson.databind.json.JsonMapper;

/**
 * End-to-end tests for contact search against a real database. Each test runs
 * in its own transaction that is rolled back afterwards.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class ContactSearchControllerIntegrationTest {

    private static final String STRONG_PASSWORD = "Str0ng!Pass";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    private final JsonMapper jsonMapper = JsonMapper.builder().build();

    @Test
    void searchRequiresAuthentication() throws Exception {
        mockMvc.perform(get("/api/contacts/search").param("q", "alice"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void searchByUsernameFindsMatch() throws Exception {
        registerAndGetToken("alice_wonder", "alice@example.com");
        String bobToken = registerAndGetToken("bob_builder", "bob@example.com");

        mockMvc.perform(searchRequest(bobToken, "alice_won"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].username").value("alice_wonder"));
    }

    @Test
    void searchByEmailFindsMatch() throws Exception {
        registerAndGetToken("carol_search", "carol.unique@example.com");
        String daveToken = registerAndGetToken("dave_search", "dave.search@example.com");

        mockMvc.perform(searchRequest(daveToken, "carol.unique"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].email").value("carol.unique@example.com"));
    }

    @Test
    void searchIsCaseInsensitive() throws Exception {
        registerAndGetToken("Erin_Case", "erin.case@example.com");
        String frankToken = registerAndGetToken("frank_case", "frank.case@example.com");

        mockMvc.perform(searchRequest(frankToken, "ERIN_CASE"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].username").value("Erin_Case"));
    }

    @Test
    void searchMatchesPartialSubstring() throws Exception {
        registerAndGetToken("grace_partial_match", "grace.partial@example.com");
        String henryToken = registerAndGetToken("henry_partial", "henry.partial@example.com");

        mockMvc.perform(searchRequest(henryToken, "partial_mat"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].username").value("grace_partial_match"));
    }

    @Test
    void searchExcludesSelf() throws Exception {
        String token = registerAndGetToken("ivan_self", "ivan.self@example.com");

        mockMvc.perform(searchRequest(token, "ivan_self"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(0)));
    }

    @Test
    void searchReturnsNoResultsForUnknownQuery() throws Exception {
        String token = registerAndGetToken("judy_none", "judy.none@example.com");

        mockMvc.perform(searchRequest(token, "nobody_matches_this_zz"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(0)));
    }

    @Test
    void searchRejectsTooShortQuery() throws Exception {
        String token = registerAndGetToken("kevin_short", "kevin.short@example.com");

        mockMvc.perform(searchRequest(token, "a"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.fieldErrors.q", org.hamcrest.Matchers.notNullValue()));
    }

    @Test
    void searchResultsExposeOnlySafeFields() throws Exception {
        registerAndGetToken("laura_safe", "laura.safe@example.com");
        String monaToken = registerAndGetToken("mona_safe", "mona.safe@example.com");

        mockMvc.perform(searchRequest(monaToken, "laura_safe"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id", org.hamcrest.Matchers.notNullValue()))
                .andExpect(jsonPath("$[0].username").value("laura_safe"))
                .andExpect(jsonPath("$[0].email").value("laura.safe@example.com"))
                .andExpect(jsonPath("$[0].passwordHash").doesNotExist());
    }

    private org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder searchRequest(
            String token, String query) {
        return get("/api/contacts/search").param("q", query).header("Authorization", "Bearer " + token);
    }

    private String registerAndGetToken(String username, String email) throws Exception {
        String body = jsonMapper.writeValueAsString(new RegisterPayload(username, email, STRONG_PASSWORD));
        MvcResult result = mockMvc.perform(
                        post("/api/auth/register").contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isCreated())
                .andReturn();
        var node = jsonMapper.readTree(result.getResponse().getContentAsString());
        UUID id = UUID.fromString(node.get("user").get("id").asString());
        userRepository.findById(id).ifPresent(user -> {
            user.setEmailVerified(true);
            userRepository.save(user);
        });
        return node.get("token").asString();
    }

    private record RegisterPayload(String username, String email, String password) {
    }
}
