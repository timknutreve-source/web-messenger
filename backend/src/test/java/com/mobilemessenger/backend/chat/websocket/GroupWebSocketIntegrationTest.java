package com.mobilemessenger.backend.chat.websocket;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

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
import org.springframework.messaging.converter.JacksonJsonMessageConverter;
import org.springframework.messaging.simp.stomp.StompHeaders;
import org.springframework.messaging.simp.stomp.StompSession;
import org.springframework.messaging.simp.stomp.StompSessionHandlerAdapter;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.socket.WebSocketHttpHeaders;
import org.springframework.web.socket.client.standard.StandardWebSocketClient;
import org.springframework.web.socket.messaging.WebSocketStompClient;

/**
 * Real-time delivery of the group features over a real WebSocket: a group
 * invitation reaching its invitee, group messages and members joining
 * reaching every member (and only members), and poll updates reaching the
 * whole group. Also covers the browser-style handshake, where the JWT rides
 * in the URL because a browser WebSocket cannot set headers.
 *
 * <p>Not {@code @Transactional} for the same reason as
 * {@code ChatWebSocketIntegrationTest}: the server side runs on its own
 * thread and DB connection, so it can't see an uncommitted test transaction.
 * Every created user (and, by cascade, their data) is removed afterwards.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureMockMvc
class GroupWebSocketIntegrationTest {

    @LocalServerPort
    private int port;

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    private ApiTestSupport api;
    private final List<UUID> createdUserIds = new ArrayList<>();
    private final List<StompSession> sessions = new ArrayList<>();

    @BeforeEach
    void setUp() {
        api = new ApiTestSupport(mockMvc, userRepository);
    }

    @AfterEach
    void cleanUp() {
        sessions.forEach(session -> {
            if (session.isConnected()) {
                session.disconnect();
            }
        });
        userRepository.deleteAllById(createdUserIds);
    }

    private TestUser user(String prefix) throws Exception {
        TestUser user = api.user(prefix + UUID.randomUUID().toString().substring(0, 6));
        createdUserIds.add(user.id());
        return user;
    }

    @Test
    void anInviteeIsToldAboutAGroupInvitationImmediately() throws Exception {
        TestUser alice = user("wa");
        TestUser bob = user("wb");
        api.becomeContacts(alice, bob);
        BlockingQueue<Map<String, Object>> events = subscribe(bob, "/topic/users/" + bob.id() + "/invitations");

        api.request("POST", "/api/groups", alice,
                Map.of("name", "Live group", "memberIds", List.of(bob.id().toString())));

        Map<String, Object> event = events.poll(5, TimeUnit.SECONDS);
        assertNotNull(event, "no NEW_GROUP_INVITATION arrived");
        assertEquals("NEW_GROUP_INVITATION", event.get("type"));
        @SuppressWarnings("unchecked")
        Map<String, Object> payload = (Map<String, Object>) event.get("payload");
        assertEquals("Live group", payload.get("groupName"));
    }

    @Test
    void everyMemberReceivesGroupMessagesAndJoinsInRealTime() throws Exception {
        TestUser alice = user("wa");
        TestUser bob = user("wb");
        TestUser carol = user("wc");
        UUID group = api.groupOf("Broadcast", alice, bob);
        api.becomeContacts(alice, carol);
        BlockingQueue<Map<String, Object>> bobEvents = subscribe(bob, "/topic/chats/" + group);

        api.request("POST", "/api/groups/" + group + "/invitations", alice, Map.of("userIds", List.of(carol.id().toString())));
        api.acceptGroupInvitation(carol, group.toString());
        api.sendMessage(alice, group, "welcome aboard");

        Map<String, Object> joined = awaitEvent(bobEvents, "MEMBER_JOINED");
        @SuppressWarnings("unchecked")
        Map<String, Object> joinedPayload = (Map<String, Object>) joined.get("payload");
        assertEquals(carol.username(), joinedPayload.get("username"));
        Map<String, Object> message = awaitEvent(bobEvents, "NEW_MESSAGE");
        @SuppressWarnings("unchecked")
        Map<String, Object> messagePayload = (Map<String, Object>) message.get("payload");
        assertEquals("welcome aboard", messagePayload.get("content"));
    }

    @Test
    void aPollUpdateReachesTheWholeGroupWithoutRevealingAnyVote() throws Exception {
        TestUser alice = user("wa");
        TestUser bob = user("wb");
        UUID group = api.groupOf("Poll live", alice, bob);
        var created = api.json(api.request("POST", "/api/chats/" + group + "/polls", alice,
                Map.of("question", "Lunch?", "options", List.of("Pizza", "Sushi"), "anonymous", true)));
        BlockingQueue<Map<String, Object>> aliceEvents = subscribe(alice, "/topic/chats/" + group);
        String pollId = created.get("poll").get("id").asString();
        String option = created.get("poll").get("options").get(0).get("id").asString();

        api.request("PUT", "/api/chats/" + group + "/polls/" + pollId + "/vote", bob, Map.of("optionId", option));

        Map<String, Object> event = awaitEvent(aliceEvents, "POLL_UPDATED");
        @SuppressWarnings("unchecked")
        Map<String, Object> payload = (Map<String, Object>) event.get("payload");
        assertEquals(pollId, payload.get("pollId"));
        assertEquals(2, payload.size(), "the event names the poll only - no tallies, no voter, no option");
    }

    @Test
    void acceptingAContactInvitationTellsTheSenderAndTheAcceptersOtherSessions() throws Exception {
        TestUser alice = user("wa");
        TestUser bob = user("wb");
        BlockingQueue<Map<String, Object>> aliceEvents = subscribe(alice, "/topic/users/" + alice.id() + "/invitations");
        BlockingQueue<Map<String, Object>> bobEvents = subscribe(bob, "/topic/users/" + bob.id() + "/invitations");

        api.becomeContacts(alice, bob);

        for (BlockingQueue<Map<String, Object>> events : List.of(aliceEvents, bobEvents)) {
            Map<String, Object> payload = payloadOf(awaitEvent(events, "INVITATION_RESOLVED"));
            assertEquals("CONTACT", payload.get("kind"));
            assertEquals(true, payload.get("accepted"));
        }
    }

    @Test
    void decliningAGroupInvitationTellsTheInviter() throws Exception {
        TestUser alice = user("wa");
        TestUser bob = user("wb");
        api.becomeContacts(alice, bob);
        BlockingQueue<Map<String, Object>> aliceEvents = subscribe(alice, "/topic/users/" + alice.id() + "/invitations");
        api.request("POST", "/api/groups", alice, Map.of("name", "Declined", "memberIds", List.of(bob.id().toString())));
        String invitationId = api.json(api.request("GET", "/api/groups/invitations/pending", bob, null))
                .get(0).get("id").asString();

        api.request("POST", "/api/groups/invitations/" + invitationId + "/decline", bob, null);

        Map<String, Object> payload = payloadOf(awaitEvent(aliceEvents, "INVITATION_RESOLVED"));
        assertEquals("GROUP", payload.get("kind"));
        assertEquals(false, payload.get("accepted"));
        assertEquals(invitationId, payload.get("invitationId"));
    }

    @Test
    void aNonMemberNeverReceivesAGroupsEvents() throws Exception {
        TestUser alice = user("wa");
        TestUser bob = user("wb");
        TestUser outsider = user("wo");
        UUID group = api.groupOf("Members only", alice, bob);
        BlockingQueue<Map<String, Object>> outsiderEvents = subscribe(outsider, "/topic/chats/" + group);

        api.sendMessage(alice, group, "not for outsiders");

        assertThrows(AssertionError.class, () -> awaitEvent(outsiderEvents, "NEW_MESSAGE", 2));
    }

    @Test
    void aBrowserStyleHandshakeWithTheTokenInTheUrlAuthenticates() throws Exception {
        TestUser alice = user("wa");
        TestUser bob = user("wb");
        UUID chat = api.becomeContacts(alice, bob);
        WebSocketStompClient client = stompClient();

        StompSession session = client.connectAsync(
                        "ws://localhost:" + port + "/ws?access_token=" + bob.token(),
                        new WebSocketHttpHeaders(),
                        new StompSessionHandlerAdapter() {})
                .get(5, TimeUnit.SECONDS);
        sessions.add(session);
        BlockingQueue<Map<String, Object>> events = new LinkedBlockingQueue<>();
        session.subscribe("/topic/chats/" + chat, collector(events));
        Thread.sleep(300);

        api.sendMessage(alice, chat, "hello browser");

        assertEquals("hello browser", payloadOf(awaitEvent(events, "NEW_MESSAGE")).get("content"));
    }

    @Test
    void aHandshakeWithAnInvalidQueryTokenIsRefused() {
        WebSocketStompClient client = stompClient();

        assertThrows(Exception.class, () -> client.connectAsync(
                        "ws://localhost:" + port + "/ws?access_token=not-a-real-token",
                        new WebSocketHttpHeaders(),
                        new StompSessionHandlerAdapter() {})
                .get(5, TimeUnit.SECONDS));
    }

    // ---- helpers ----

    private BlockingQueue<Map<String, Object>> subscribe(TestUser user, String destination) throws Exception {
        WebSocketHttpHeaders handshake = new WebSocketHttpHeaders();
        handshake.add("Authorization", "Bearer " + user.token());
        StompSession session = stompClient()
                .connectAsync("ws://localhost:" + port + "/ws", handshake, new StompSessionHandlerAdapter() {})
                .get(5, TimeUnit.SECONDS);
        sessions.add(session);
        BlockingQueue<Map<String, Object>> events = new LinkedBlockingQueue<>();
        session.subscribe(destination, collector(events));
        Thread.sleep(300);
        return events;
    }

    private StompSessionHandlerAdapter collector(BlockingQueue<Map<String, Object>> events) {
        return new StompSessionHandlerAdapter() {
            @Override
            public Type getPayloadType(StompHeaders headers) {
                return Map.class;
            }

            @Override
            @SuppressWarnings("unchecked")
            public void handleFrame(StompHeaders headers, Object payload) {
                events.add((Map<String, Object>) payload);
            }
        };
    }

    private Map<String, Object> awaitEvent(BlockingQueue<Map<String, Object>> events, String type) throws Exception {
        return awaitEvent(events, type, 5);
    }

    private Map<String, Object> awaitEvent(BlockingQueue<Map<String, Object>> events, String type, int seconds)
            throws Exception {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(seconds);
        while (System.nanoTime() < deadline) {
            Map<String, Object> event = events.poll(200, TimeUnit.MILLISECONDS);
            if (event != null && type.equals(event.get("type"))) {
                return event;
            }
        }
        throw new AssertionError("no " + type + " event arrived within " + seconds + "s");
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> payloadOf(Map<String, Object> event) {
        assertTrue(event.get("payload") instanceof Map);
        return (Map<String, Object>) event.get("payload");
    }

    private WebSocketStompClient stompClient() {
        WebSocketStompClient client = new WebSocketStompClient(new StandardWebSocketClient());
        client.setMessageConverter(new JacksonJsonMessageConverter());
        return client;
    }
}
