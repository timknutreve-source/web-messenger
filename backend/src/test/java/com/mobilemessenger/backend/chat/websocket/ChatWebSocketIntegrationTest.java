package com.mobilemessenger.backend.chat.websocket;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.mobilemessenger.backend.chat.ConversationRepository;
import com.mobilemessenger.backend.chat.MessageRepository;
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
import org.springframework.data.domain.PageRequest;
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
 * End-to-end tests for the STOMP/WebSocket layer: handshake authentication,
 * per-conversation subscription authorization, and typing events.
 *
 * <p>Unlike every other integration test in this codebase, this class is
 * deliberately <b>not</b> {@code @Transactional}: a real WebSocket
 * connection is served on its own server thread with its own database
 * connection, which would not see an uncommitted transaction still open on
 * the test's thread. Its REST setup calls (register/invite/accept) therefore
 * genuinely commit, so every user created here is tracked and deleted in
 * {@link #cleanUp()} - cascading deletes (see V4-V6 migrations) take the
 * user's contacts, conversations, participants and messages with it. Random
 * per-run username suffixes are kept as a second line of defense in case a
 * test fails before cleanup runs.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureMockMvc
class ChatWebSocketIntegrationTest {

    private static final String STRONG_PASSWORD = "Str0ng!Pass";

    @LocalServerPort
    private int port;

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ConversationRepository conversationRepository;

    @Autowired
    private MessageRepository messageRepository;

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
    void authenticatedParticipantCanConnectAndSubscribeToTheirOwnConversation() throws Exception {
        RegisteredUser alice = register("alice_ws_ok");
        RegisteredUser bob = register("bob_ws_ok");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        StompSession session = connect(alice.token());
        try {
            session.subscribe("/topic/chats/" + chatId, new StompSessionHandlerAdapter() {});
            // A rejected subscription would have sent an ERROR frame and
            // closed the session by now; give the broker a moment.
            Thread.sleep(300);
            assertTrue(session.isConnected());
        } finally {
            session.disconnect();
        }
    }

    @Test
    void connectingWithoutAuthenticationIsRejected() {
        WebSocketStompClient client = stompClient();
        CompletableFuture<StompSession> future =
                client.connectAsync(wsUrl(), new StompSessionHandlerAdapter() {});
        assertThrows(Exception.class, () -> future.get(5, TimeUnit.SECONDS));
    }

    /**
     * The channel interceptor rejects the SUBSCRIBE by throwing from {@code
     * preSend}, which runs on the inbound channel's own executor thread -
     * that prevents the subscription from ever being registered with the
     * broker, but doesn't reliably surface as a client-visible STOMP ERROR
     * frame in every Spring version/transport combination. So rather than
     * asserting on an error signal, this proves the property that actually
     * matters: a non-participant's "subscription" never receives a real
     * event broadcast on that conversation's topic.
     */
    @Test
    void nonParticipantNeverReceivesEventsFromSomeoneElsesConversation() throws Exception {
        RegisteredUser alice = register("alice_ws_priv");
        RegisteredUser bob = register("bob_ws_priv");
        RegisteredUser carol = register("carol_ws_priv");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        StompSession carolSession = connect(carol.token());
        StompSession aliceSession = connect(alice.token());
        try {
            CompletableFuture<Object> received = new CompletableFuture<>();
            carolSession.subscribe(
                    "/topic/chats/" + chatId,
                    new StompSessionHandlerAdapter() {
                        @Override
                        public void handleFrame(StompHeaders headers, Object payload) {
                            received.complete(payload);
                        }
                    });
            Thread.sleep(300);

            sendMessage(alice.token(), chatId, "hello bob, not carol");

            assertThrows(Exception.class, () -> received.get(2, TimeUnit.SECONDS));
        } finally {
            // The rejected SUBSCRIBE tears down carol's whole connection
            // (see the Javadoc above), so it may already be closed here.
            if (carolSession.isConnected()) {
                carolSession.disconnect();
            }
            if (aliceSession.isConnected()) {
                aliceSession.disconnect();
            }
        }
    }

    @Test
    void typingEventCarriesTheAuthenticatedSendersIdentityAndIsNeverPersisted() throws Exception {
        RegisteredUser alice = register("alice_ws_typing");
        RegisteredUser bob = register("bob_ws_typing");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        StompSession bobSession = connect(bob.token());
        StompSession aliceSession = connect(alice.token());
        try {
            CompletableFuture<Map<String, Object>> received = new CompletableFuture<>();
            bobSession.subscribe(
                    "/topic/chats/" + chatId,
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

            aliceSession.send("/app/chats/" + chatId + "/typing", new TypingRequest(true));

            Map<String, Object> event = received.get(5, TimeUnit.SECONDS);
            assertEquals("TYPING_STARTED", event.get("type"));
            @SuppressWarnings("unchecked")
            Map<String, Object> typingPayload = (Map<String, Object>) event.get("payload");
            assertEquals(alice.id().toString(), typingPayload.get("userId"));
            assertEquals(alice.username(), typingPayload.get("username"));

            assertEquals(
                    0,
                    messageRepository
                            .findByConversationIdOrderByCreatedAtDescIdDesc(chatId, PageRequest.of(0, 10))
                            .size());
        } finally {
            aliceSession.disconnect();
            bobSession.disconnect();
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

    private UUID becomeContactsAndGetChatId(RegisteredUser sender, RegisteredUser recipient) throws Exception {
        UUID invitationId = sendInvitationAndGetId(sender.token(), recipient.id());
        mockMvc.perform(post("/api/contacts/invitations/" + invitationId + "/accept")
                        .header("Authorization", "Bearer " + recipient.token()))
                .andExpect(status().isOk());

        boolean senderIsLower = sender.id().toString().compareTo(recipient.id().toString()) < 0;
        UUID low = senderIsLower ? sender.id() : recipient.id();
        UUID high = senderIsLower ? recipient.id() : sender.id();
        return conversationRepository.findByDirectUserAIdAndDirectUserBId(low, high).orElseThrow().getId();
    }

    private void sendMessage(String token, UUID chatId, String content) throws Exception {
        mockMvc.perform(post("/api/chats/" + chatId + "/messages")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(jsonMapper.writeValueAsString(new SendMessagePayload(content)))
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isCreated());
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
        return new RegisteredUser(id, token, username);
    }

    private record RegisteredUser(UUID id, String token, String username) {
    }

    private record RegisterPayload(String username, String email, String password) {
    }

    private record SendInvitationPayload(UUID recipientId) {
    }

    private record SendMessagePayload(String content) {
    }
}
