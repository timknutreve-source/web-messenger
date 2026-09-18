package com.mobilemessenger.backend.contact;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.mobilemessenger.backend.user.UserRepository;
import java.lang.reflect.Type;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.AfterEach;
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
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.web.socket.WebSocketHttpHeaders;
import org.springframework.web.socket.client.standard.StandardWebSocketClient;
import org.springframework.web.socket.messaging.WebSocketStompClient;
import tools.jackson.databind.json.JsonMapper;

/**
 * End-to-end tests proving a new invitation reaches its recipient
 * immediately over WebSocket, while never leaking to anyone else's
 * connection - see {@code ContactInvitationService.sendInvitation} (the
 * broadcast) and {@code ChatSubscriptionInterceptor} (the per-user topic
 * authorization check).
 *
 * <p>Not {@code @Transactional}, for the same reason as {@code
 * ChatWebSocketIntegrationTest}: a real WebSocket connection runs on its own
 * server thread/DB connection, which wouldn't see an uncommitted transaction
 * on the test thread. Every created user is cleaned up in {@link #cleanUp()}.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureMockMvc
class ContactInvitationWebSocketIntegrationTest {

    private static final String STRONG_PASSWORD = "Str0ng!Pass";

    @LocalServerPort
    private int port;

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    private final JsonMapper jsonMapper = JsonMapper.builder().build();
    private final List<UUID> createdUserIds = new ArrayList<>();

    @AfterEach
    void cleanUp() {
        userRepository.deleteAllById(createdUserIds);
        createdUserIds.clear();
    }

    @Test
    void recipientReceivesNewInvitationEventInRealTime() throws Exception {
        RegisteredUser alice = register("alice_ws_inv");
        RegisteredUser bob = register("bob_ws_inv");

        StompSession bobSession = connect(bob.token());
        try {
            CompletableFuture<Map<String, Object>> received = new CompletableFuture<>();
            bobSession.subscribe(
                    "/topic/users/" + bob.id() + "/invitations",
                    new StompSessionHandlerAdapter() {
                        @Override
                        public Type getPayloadType(StompHeaders headers) {
                            return Map.class;
                        }

                        @Override
                        @SuppressWarnings("unchecked")
                        public void handleFrame(StompHeaders headers, Object payload) {
                            received.complete((Map<String, Object>) payload);
                        }
                    });
            Thread.sleep(200);

            sendInvitation(alice.token(), bob.id());

            Map<String, Object> event = received.get(5, TimeUnit.SECONDS);
            assertEquals("NEW_INVITATION", event.get("type"));
            @SuppressWarnings("unchecked")
            Map<String, Object> payload = (Map<String, Object>) event.get("payload");
            @SuppressWarnings("unchecked")
            Map<String, Object> sender = (Map<String, Object>) payload.get("sender");
            assertEquals(alice.username(), sender.get("username"));
        } finally {
            bobSession.disconnect();
        }
    }

    /**
     * Same reasoning as {@code ChatWebSocketIntegrationTest
     * .nonParticipantNeverReceivesEventsFromSomeoneElsesConversation}: the
     * channel interceptor's rejection doesn't reliably surface as a
     * client-visible STOMP error frame across transports, so this asserts
     * the property that actually matters - carol's "subscription" to bob's
     * personal topic never actually receives bob's invitation.
     */
    @Test
    void userCannotSubscribeToAnotherUsersInvitationsTopic() throws Exception {
        RegisteredUser alice = register("alice_ws_inv_priv");
        RegisteredUser bob = register("bob_ws_inv_priv");
        RegisteredUser carol = register("carol_ws_inv_priv");

        StompSession carolSession = connect(carol.token());
        try {
            CompletableFuture<Object> received = new CompletableFuture<>();
            carolSession.subscribe(
                    "/topic/users/" + bob.id() + "/invitations",
                    new StompSessionHandlerAdapter() {
                        @Override
                        public void handleFrame(StompHeaders headers, Object payload) {
                            received.complete(payload);
                        }
                    });
            Thread.sleep(300);

            sendInvitation(alice.token(), bob.id());

            assertThrows(Exception.class, () -> received.get(2, TimeUnit.SECONDS));
        } finally {
            if (carolSession.isConnected()) {
                carolSession.disconnect();
            }
        }
    }

    // ---- helpers ----

    private StompSession connect(String token) throws Exception {
        WebSocketStompClient client = stompClient();
        WebSocketHttpHeaders handshakeHeaders = new WebSocketHttpHeaders();
        handshakeHeaders.add("Authorization", "Bearer " + token);
        return client.connectAsync(wsUrl(), handshakeHeaders, new StompSessionHandlerAdapter() {})
                .get(5, TimeUnit.SECONDS);
    }

    private WebSocketStompClient stompClient() {
        WebSocketStompClient client = new WebSocketStompClient(new StandardWebSocketClient());
        client.setMessageConverter(new JacksonJsonMessageConverter());
        return client;
    }

    private String wsUrl() {
        return "ws://localhost:" + port + "/ws";
    }

    private void sendInvitation(String senderToken, UUID recipientId) throws Exception {
        String body = jsonMapper.writeValueAsString(new SendInvitationPayload(recipientId));
        mockMvc.perform(post("/api/contacts/invitations")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body)
                        .header("Authorization", "Bearer " + senderToken))
                .andExpect(status().isCreated());
    }

    private RegisteredUser register(String usernamePrefix) throws Exception {
        String suffix = UUID.randomUUID().toString().substring(0, 8);
        String username = usernamePrefix + "_" + suffix;
        String email = usernamePrefix.replace('_', '.') + "." + suffix + "@example.com";
        String body = jsonMapper.writeValueAsString(new RegisterPayload(username, email, STRONG_PASSWORD));
        MvcResult result = mockMvc.perform(
                        post("/api/auth/register").contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isCreated())
                .andReturn();
        var node = jsonMapper.readTree(result.getResponse().getContentAsString());
        String token = node.get("token").asString();
        UUID id = UUID.fromString(node.get("user").get("id").asString());
        createdUserIds.add(id);
        userRepository.findById(id).ifPresent(user -> {
            user.setEmailVerified(true);
            userRepository.save(user);
        });
        return new RegisteredUser(id, token, username);
    }

    private record RegisteredUser(UUID id, String token, String username) {
    }

    private record RegisterPayload(String username, String email, String password) {
    }

    private record SendInvitationPayload(UUID recipientId) {
    }
}
