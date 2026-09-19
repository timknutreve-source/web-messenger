package com.mobilemessenger.backend.chat.websocket;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.mobilemessenger.backend.support.ApiTestSupport;
import com.mobilemessenger.backend.support.ApiTestSupport.TestUser;
import com.mobilemessenger.backend.user.UserRepository;
import java.lang.reflect.Type;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.messaging.converter.JacksonJsonMessageConverter;
import org.springframework.messaging.simp.stomp.StompHeaders;
import org.springframework.messaging.simp.stomp.StompSession;
import org.springframework.messaging.simp.stomp.StompSessionHandlerAdapter;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;
import org.springframework.web.socket.WebSocketHttpHeaders;
import org.springframework.web.socket.client.standard.StandardWebSocketClient;
import org.springframework.web.socket.messaging.WebSocketStompClient;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

/**
 * Cross-platform behaviour of the one shared backend: the same account signed
 * in on a phone (JWT in an HTTP header on the WebSocket handshake) and in a
 * browser (JWT in the URL - a browser WebSocket cannot set headers) at once.
 *
 * <ul>
 *   <li>Web -> Mobile: something done on the web session reaches the mobile
 *       session (and the other person) in real time, and vice versa.</li>
 *   <li>The two sessions are independent: ending one leaves the other working.</li>
 * </ul>
 *
 * <p>Not {@code @Transactional}: the WebSocket side runs on its own thread
 * and connection. Created users are deleted afterwards.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureMockMvc
class CrossPlatformSyncIntegrationTest {

    private static final long LIVE_LIMIT_MS = 2000;
    private static final String PASSWORD = ApiTestSupport.PASSWORD;

    @LocalServerPort
    private int port;

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    private final JsonMapper jsonMapper = JsonMapper.builder().build();
    private final List<UUID> createdUserIds = new ArrayList<>();
    private final List<StompSession> sessions = new ArrayList<>();
    private ApiTestSupport api;

    @BeforeEach
    void setUp() {
        api = new ApiTestSupport(mockMvc, userRepository);
    }

    @AfterEach
    void cleanUp() {
        sessions.forEach(s -> {
            if (s.isConnected()) {
                s.disconnect();
            }
        });
        userRepository.deleteAllById(createdUserIds);
    }

    private TestUser user(String prefix) throws Exception {
        TestUser u = api.user(prefix + UUID.randomUUID().toString().substring(0, 6));
        createdUserIds.add(u.id());
        return u;
    }

    /** A second login of the same account, labelled as coming from the given device. */
    private String login(TestUser who, String deviceName) throws Exception {
        String body = jsonMapper.writeValueAsString(
                Map.of("usernameOrEmail", who.username(), "password", PASSWORD, "deviceName", deviceName));
        var result = mockMvc.perform(MockMvcRequestBuilders.post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isOk())
                .andReturn();
        return jsonMapper.readTree(result.getResponse().getContentAsString()).get("token").asString();
    }

    private TestUser sessionOf(TestUser who, String token) {
        return new TestUser(who.id(), who.username(), token);
    }

    private BlockingQueue<Map<String, Object>> subscribeMobileStyle(String token, String destination) throws Exception {
        WebSocketHttpHeaders headers = new WebSocketHttpHeaders();
        headers.add("Authorization", "Bearer " + token);
        return subscribe(stompClient().connectAsync(wsUrl(""), headers, new StompSessionHandlerAdapter() {}), destination);
    }

    private BlockingQueue<Map<String, Object>> subscribeWebStyle(String token, String destination) throws Exception {
        return subscribe(
                stompClient().connectAsync(
                        wsUrl("?access_token=" + token), new WebSocketHttpHeaders(), new StompSessionHandlerAdapter() {}),
                destination);
    }

    private BlockingQueue<Map<String, Object>> subscribe(
            java.util.concurrent.CompletableFuture<StompSession> connecting, String destination) throws Exception {
        StompSession session = connecting.get(5, TimeUnit.SECONDS);
        sessions.add(session);
        BlockingQueue<Map<String, Object>> events = new LinkedBlockingQueue<>();
        session.subscribe(destination, new StompSessionHandlerAdapter() {
            @Override
            public Type getPayloadType(StompHeaders headers) {
                return Map.class;
            }

            @Override
            @SuppressWarnings("unchecked")
            public void handleFrame(StompHeaders headers, Object payload) {
                events.add((Map<String, Object>) payload);
            }
        });
        Thread.sleep(300);
        return events;
    }

    /** Waits for an event of {@code type}; returns how long it took. */
    private long awaitEvent(BlockingQueue<Map<String, Object>> events, String type, String contentContains)
            throws Exception {
        long start = System.nanoTime();
        while (System.nanoTime() - start < TimeUnit.SECONDS.toNanos(6)) {
            Map<String, Object> event = events.poll(100, TimeUnit.MILLISECONDS);
            if (event != null && type.equals(event.get("type"))) {
                @SuppressWarnings("unchecked")
                Map<String, Object> payload = (Map<String, Object>) event.get("payload");
                if (contentContains == null || contentContains.equals(payload.get("content"))) {
                    return TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - start);
                }
            }
        }
        throw new AssertionError("no " + type + " event within 6s");
    }


    private WebSocketStompClient stompClient() {
        WebSocketStompClient client = new WebSocketStompClient(new StandardWebSocketClient());
        client.setMessageConverter(new JacksonJsonMessageConverter());
        return client;
    }

    private String wsUrl(String suffix) {
        return "ws://localhost:" + port + "/ws" + suffix;
    }

    // ---------------------------------------------------------------------

    @Test
    void webToMobile_aMessageSentFromTheWebSessionReachesTheMobileSessionAndThePartner() throws Exception {
        TestUser alice = user("xa");
        TestUser bob = user("xb");
        UUID chat = api.becomeContacts(alice, bob);
        TestUser aliceWeb = sessionOf(alice, login(alice, "Web"));
        TestUser aliceMobile = sessionOf(alice, login(alice, "Android"));
        String topic = "/topic/chats/" + chat;
        BlockingQueue<Map<String, Object>> mobileEvents = subscribeMobileStyle(aliceMobile.token(), topic);
        BlockingQueue<Map<String, Object>> bobEvents = subscribeMobileStyle(bob.token(), topic);

        api.sendMessage(aliceWeb, chat, "sent from the web");

        assertThat(awaitEvent(mobileEvents, "NEW_MESSAGE", "sent from the web")).isLessThan(LIVE_LIMIT_MS);
        assertThat(awaitEvent(bobEvents, "NEW_MESSAGE", "sent from the web")).isLessThan(LIVE_LIMIT_MS);
        // Same account, either session: the history is one and the same.
        for (TestUser session : List.of(aliceWeb, aliceMobile)) {
            api.request("GET", "/api/chats/" + chat + "/messages", session, null)
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.messages[0].content").value("sent from the web"));
        }
    }

    @Test
    void mobileToWeb_aMessageFromThePartnerReachesABrowserStyleConnectionInRealTime() throws Exception {
        TestUser alice = user("xa");
        TestUser bob = user("xb");
        UUID chat = api.becomeContacts(alice, bob);
        String aliceWebToken = login(alice, "Web");
        BlockingQueue<Map<String, Object>> webEvents = subscribeWebStyle(aliceWebToken, "/topic/chats/" + chat);

        api.sendMessage(bob, chat, "sent from the phone");

        assertThat(awaitEvent(webEvents, "NEW_MESSAGE", "sent from the phone")).isLessThan(LIVE_LIMIT_MS);
    }

    @Test
    void theMobileSessionSeesWhatTheWebSessionDidToTheAccountAsItHappens() throws Exception {
        // A contact accepted on the web, a group created on the web, a poll voted on the web:
        // the mobile session's personal feed / chat topics carry each one.
        TestUser alice = user("xa");
        TestUser bob = user("xb");
        TestUser aliceWeb = sessionOf(alice, login(alice, "Web"));
        String mobileToken = login(alice, "Android");
        BlockingQueue<Map<String, Object>> mobileFeed =
                subscribeMobileStyle(mobileToken, "/topic/users/" + alice.id() + "/invitations");
        var invitation = api.json(api.request("POST", "/api/contacts/invitations", bob, Map.of("recipientId", alice.id().toString()))
                .andExpect(status().isCreated()));
        awaitEvent(mobileFeed, "NEW_INVITATION", null);

        api.request("POST", "/api/contacts/invitations/" + invitation.get("id").asString() + "/accept", aliceWeb, null)
                .andExpect(status().isOk());

        // The web session accepted; the mobile session is told the invitation is settled.
        assertThat(awaitEvent(mobileFeed, "INVITATION_RESOLVED", null)).isLessThan(LIVE_LIMIT_MS);
    }

    @Test
    void sessionsAreIndependent_endingTheWebSessionLeavesTheMobileSessionAndItsSocketWorking() throws Exception {
        TestUser alice = user("xa");
        TestUser bob = user("xb");
        UUID chat = api.becomeContacts(alice, bob);
        String webToken = login(alice, "Web");
        String mobileToken = login(alice, "Android");
        TestUser aliceWeb = sessionOf(alice, webToken);
        TestUser aliceMobile = sessionOf(alice, mobileToken);
        BlockingQueue<Map<String, Object>> mobileEvents = subscribeMobileStyle(mobileToken, "/topic/chats/" + chat);

        api.request("POST", "/api/auth/logout", aliceWeb, null).andExpect(status().isNoContent());

        // The web token is dead server-side...
        api.request("GET", "/api/auth/me", aliceWeb, null).andExpect(status().isUnauthorized());
        // ...while the mobile session keeps working over REST and its open socket.
        api.request("GET", "/api/auth/me", aliceMobile, null).andExpect(status().isOk());
        api.sendMessage(bob, chat, "still there?");
        assertNotNull(awaitEvent(mobileEvents, "NEW_MESSAGE", "still there?"));
        api.request("POST", "/api/chats/" + chat + "/messages", aliceMobile, Map.of("content", "yes"))
                .andExpect(status().isCreated());
    }

    @Test
    void aRevokedWebSessionCannotOpenANewBrowserStyleSocket() throws Exception {
        TestUser alice = user("xa");
        String webToken = login(alice, "Web");
        api.request("POST", "/api/auth/logout", sessionOf(alice, webToken), null).andExpect(status().isNoContent());

        org.junit.jupiter.api.Assertions.assertThrows(Exception.class, () -> stompClient()
                .connectAsync(wsUrl("?access_token=" + webToken), new WebSocketHttpHeaders(), new StompSessionHandlerAdapter() {})
                .get(5, TimeUnit.SECONDS));
    }

    @Test
    void theSameAccountCanHoldAWebAndAMobileSocketAtOnce() throws Exception {
        TestUser alice = user("xa");
        TestUser bob = user("xb");
        UUID chat = api.becomeContacts(alice, bob);
        BlockingQueue<Map<String, Object>> web = subscribeWebStyle(login(alice, "Web"), "/topic/chats/" + chat);
        BlockingQueue<Map<String, Object>> mobile = subscribeMobileStyle(login(alice, "Android"), "/topic/chats/" + chat);

        api.sendMessage(bob, chat, "to both");

        assertThat(awaitEvent(web, "NEW_MESSAGE", "to both")).isLessThan(LIVE_LIMIT_MS);
        assertThat(awaitEvent(mobile, "NEW_MESSAGE", "to both")).isLessThan(LIVE_LIMIT_MS);
    }
}
