package com.mobilemessenger.backend.auth;

import static org.hamcrest.Matchers.hasSize;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.mobilemessenger.backend.user.UserRepository;
import java.util.UUID;
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
 * "Independent sessions" and "selective logout": the same account signed in
 * on several devices at once (say Android and a web browser), where signing
 * out of one must never sign out another.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class AuthSessionControllerIntegrationTest {

    private static final String PASSWORD = "Str0ng!Pass";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    private final JsonMapper jsonMapper = JsonMapper.builder().build();

    @Test
    void theSameAccountCanBeSignedInOnSeveralDevicesAtOnce() throws Exception {
        String android = registerVerified("sess_multi", "sess.multi@example.com", "Android");
        String web = login("sess_multi", "Web");

        assertSignedIn(android);
        assertSignedIn(web);
        mockMvc.perform(get("/api/auth/sessions").header("Authorization", "Bearer " + web))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(2)));
    }

    @Test
    void loggingOutOneDeviceLeavesTheOtherSignedIn() throws Exception {
        String android = registerVerified("sess_logout", "sess.logout@example.com", "Android");
        String web = login("sess_logout", "Web");

        mockMvc.perform(post("/api/auth/logout").header("Authorization", "Bearer " + web))
                .andExpect(status().isNoContent());

        // The web session is really over - the server rejects its token, not
        // merely the client forgetting it...
        mockMvc.perform(get("/api/auth/me").header("Authorization", "Bearer " + web))
                .andExpect(status().isUnauthorized());
        // ...while the Android session is completely unaffected.
        assertSignedIn(android);
    }

    @Test
    void sessionsListMarksTheCallersOwnSessionAndShowsDeviceLabels() throws Exception {
        String android = registerVerified("sess_list", "sess.list@example.com", "Android");
        login("sess_list", "Web");

        MvcResult result = mockMvc.perform(get("/api/auth/sessions").header("Authorization", "Bearer " + android))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(2)))
                .andReturn();

        var sessions = jsonMapper.readTree(result.getResponse().getContentAsString());
        int current = 0;
        boolean sawAndroid = false;
        boolean sawWeb = false;
        for (var session : sessions) {
            if (session.get("current").asBoolean()) {
                current++;
                sawAndroid = session.get("deviceLabel").asString().equals("Android");
            }
            sawWeb |= session.get("deviceLabel").asString().equals("Web");
        }
        org.junit.jupiter.api.Assertions.assertEquals(1, current, "exactly one session is the caller's own");
        org.junit.jupiter.api.Assertions.assertTrue(sawAndroid, "the caller's own session is the Android one");
        org.junit.jupiter.api.Assertions.assertTrue(sawWeb);
    }

    @Test
    void anotherSessionOfTheSameAccountCanBeSignedOutRemotely() throws Exception {
        String android = registerVerified("sess_remote", "sess.remote@example.com", "Android");
        String web = login("sess_remote", "Web");
        UUID webSessionId = sessionIdWithLabel(android, "Web");

        mockMvc.perform(delete("/api/auth/sessions/" + webSessionId).header("Authorization", "Bearer " + android))
                .andExpect(status().isNoContent());

        mockMvc.perform(get("/api/auth/me").header("Authorization", "Bearer " + web))
                .andExpect(status().isUnauthorized());
        assertSignedIn(android);
    }

    @Test
    void aUserCannotSignOutSomeoneElsesSession() throws Exception {
        String alice = registerVerified("sess_alice", "sess.alice@example.com", "Android");
        String mallory = registerVerified("sess_mallory", "sess.mallory@example.com", "Android");
        UUID aliceSessionId = sessionIdWithLabel(alice, "Android");

        mockMvc.perform(delete("/api/auth/sessions/" + aliceSessionId).header("Authorization", "Bearer " + mallory))
                .andExpect(status().isNotFound());
        assertSignedIn(alice);
    }

    @Test
    void anUnverifiedAccountCanStillLogOut() throws Exception {
        // Registration leaves the account unverified (which blocks most of
        // the API) - the way out of that state must never be blocked too.
        String token = register("sess_unverified", "sess.unverified@example.com", "Web");

        mockMvc.perform(post("/api/auth/logout").header("Authorization", "Bearer " + token))
                .andExpect(status().isNoContent());
        mockMvc.perform(get("/api/auth/me").header("Authorization", "Bearer " + token))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void theQueryStringTokenIsNotAcceptedOutsideTheWebSocketHandshake() throws Exception {
        String token = registerVerified("sess_query", "sess.query@example.com", "Web");

        // Only /ws honors ?access_token= (a browser WebSocket cannot send
        // headers); an ordinary REST call must not authenticate that way.
        mockMvc.perform(get("/api/auth/me").param("access_token", token))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void logoutWithoutAValidTokenIsRejected() throws Exception {
        mockMvc.perform(post("/api/auth/logout")).andExpect(status().isUnauthorized());
    }

    private void assertSignedIn(String token) throws Exception {
        mockMvc.perform(get("/api/auth/me").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk());
    }

    private UUID sessionIdWithLabel(String token, String label) throws Exception {
        MvcResult result = mockMvc.perform(get("/api/auth/sessions").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andReturn();
        for (var session : jsonMapper.readTree(result.getResponse().getContentAsString())) {
            if (session.get("deviceLabel").asString().equals(label)) {
                return UUID.fromString(session.get("id").asString());
            }
        }
        throw new IllegalStateException("No session labeled " + label);
    }

    /** Registers an account and marks it verified, so the whole API (not just auth) is reachable. */
    private String registerVerified(String username, String email, String deviceName) throws Exception {
        String token = register(username, email, deviceName);
        userRepository.findByEmail(email).ifPresent(user -> {
            user.setEmailVerified(true);
            userRepository.save(user);
        });
        return token;
    }

    private String register(String username, String email, String deviceName) throws Exception {
        String body = jsonMapper.writeValueAsString(new RegisterPayload(username, email, PASSWORD, deviceName));
        return tokenFrom(mockMvc.perform(
                        post("/api/auth/register").contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isCreated())
                .andReturn());
    }

    private String login(String username, String deviceName) throws Exception {
        String body = jsonMapper.writeValueAsString(new LoginPayload(username, PASSWORD, deviceName));
        return tokenFrom(mockMvc.perform(
                        post("/api/auth/login").contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isOk())
                .andReturn());
    }

    private String tokenFrom(MvcResult result) throws Exception {
        return jsonMapper.readTree(result.getResponse().getContentAsString()).get("token").asString();
    }

    private record RegisterPayload(String username, String email, String password, String deviceName) {
    }

    private record LoginPayload(String usernameOrEmail, String password, String deviceName) {
    }
}
