package com.mobilemessenger.backend.chat;

import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.notNullValue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.transaction.annotation.Transactional;
import com.mobilemessenger.backend.user.UserRepository;
import tools.jackson.databind.json.JsonMapper;

/**
 * End-to-end tests for the Phase 6 chat list: conversation creation on
 * invitation acceptance, the active/archived chat list endpoints, sorting,
 * and archive/unarchive, against a real database. Each test runs in its own
 * transaction that is rolled back afterwards.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class ChatControllerIntegrationTest {

    private static final String STRONG_PASSWORD = "Str0ng!Pass";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ConversationRepository conversationRepository;

    @Autowired
    private ConversationParticipantRepository participantRepository;

    @Autowired
    private ChatService chatService;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @PersistenceContext
    private EntityManager entityManager;

    @Autowired
    private UserRepository userRepository;

    private final JsonMapper jsonMapper = JsonMapper.builder().build();

    // ---- conversation creation on invitation acceptance ----

    @Test
    void acceptingInvitationCreatesConversationWithBothParticipants() throws Exception {
        RegisteredUser alice = register("alice_chat_create", "alice.chat.create@example.com");
        RegisteredUser bob = register("bob_chat_create", "bob.chat.create@example.com");

        becomeContacts(alice, bob);

        UUID conversationId = directConversationId(alice.id, bob.id);
        assertTrue(participantRepository.findByConversationIdAndUserId(conversationId, alice.id).isPresent());
        assertTrue(participantRepository.findByConversationIdAndUserId(conversationId, bob.id).isPresent());
    }

    @Test
    void acceptingInvitationDoesNotCreateDuplicateConversation() throws Exception {
        RegisteredUser alice = register("alice_chat_dup", "alice.chat.dup@example.com");
        RegisteredUser bob = register("bob_chat_dup", "bob.chat.dup@example.com");

        becomeContacts(alice, bob);
        UUID firstCallId = directConversationId(alice.id, bob.id);

        // Calling getOrCreateDirectConversation again for the same pair (in
        // either order) must return the same conversation, never create a
        // second one.
        Conversation again = chatService.getOrCreateDirectConversation(bob.id, alice.id);
        assertEquals(firstCallId, again.getId());
    }

    @Test
    void newlyCreatedChatIsNonArchivedForBothUsers() throws Exception {
        RegisteredUser alice = register("alice_chat_nonarch", "alice.chat.nonarch@example.com");
        RegisteredUser bob = register("bob_chat_nonarch", "bob.chat.nonarch@example.com");

        becomeContacts(alice, bob);

        activeChats(alice.token)
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].archived").value(false));
        activeChats(bob.token)
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].archived").value(false));
    }

    // ---- active chat list ----

    @Test
    void activeChatsRequiresAuthentication() throws Exception {
        mockMvc.perform(get("/api/chats")).andExpect(status().isUnauthorized());
    }

    @Test
    void emptyChatListWorks() throws Exception {
        RegisteredUser alice = register("alice_chat_empty", "alice.chat.empty@example.com");

        activeChats(alice.token).andExpect(status().isOk()).andExpect(jsonPath("$", hasSize(0)));
    }

    @Test
    void userSeesOwnChatsWithCorrectOtherUserInfo() throws Exception {
        RegisteredUser alice = register("alice_chat_info", "alice.chat.info@example.com");
        RegisteredUser bob = register("bob_chat_info", "bob.chat.info@example.com");

        becomeContacts(alice, bob);

        activeChats(alice.token)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].id", notNullValue()))
                .andExpect(jsonPath("$[0].otherUser.username").value("bob_chat_info"))
                .andExpect(jsonPath("$[0].lastActivityAt", notNullValue()));

        activeChats(bob.token)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].otherUser.username").value("alice_chat_info"));
    }

    @Test
    void unrelatedUserDoesNotSeeSomeoneElsesChats() throws Exception {
        RegisteredUser alice = register("alice_chat_unrel", "alice.chat.unrel@example.com");
        RegisteredUser bob = register("bob_chat_unrel", "bob.chat.unrel@example.com");
        RegisteredUser carol = register("carol_chat_unrel", "carol.chat.unrel@example.com");

        becomeContacts(alice, bob);

        activeChats(carol.token).andExpect(status().isOk()).andExpect(jsonPath("$", hasSize(0)));
    }

    /**
     * Regression test for a real-world failure: a conversation whose most
     * recent message was encrypted under a since-rotated/replaced {@code
     * ENCRYPTION_MASTER_KEY} (or otherwise corrupted) previously took down
     * the *entire* chat list with a 500 the moment {@link ChatService} tried
     * to decrypt it for the preview - every other, perfectly healthy
     * conversation became unreachable too. It must instead degrade to no
     * preview for just that one conversation.
     */
    @Test
    void aConversationWithAnUndecryptableLastMessageDoesNotBreakTheWholeChatList() throws Exception {
        RegisteredUser alice = register("alice_chat_baddecrypt", "alice.chat.baddecrypt@example.com");
        RegisteredUser bob = register("bob_chat_baddecrypt", "bob.chat.baddecrypt@example.com");
        RegisteredUser carol = register("carol_chat_baddecrypt", "carol.chat.baddecrypt@example.com");

        becomeContacts(alice, bob);
        becomeContacts(alice, carol);

        UUID bobConversationId = directConversationId(alice.id, bob.id);
        sendMessage(alice.token, bobConversationId, "this will be corrupted").andExpect(status().isCreated());
        sendMessage(alice.token, directConversationId(alice.id, carol.id), "a perfectly normal message")
                .andExpect(status().isCreated());

        // Simulates ciphertext EncryptionService can never decrypt - not
        // valid Base64 at all, so this deterministically throws rather than
        // depending on an AES-GCM auth-tag mismatch against some other key.
        // A real-world stale/rotated-key mismatch fails the exact same way
        // (DecryptionException), just for a different reason inside
        // EncryptionService.decrypt() - either path must be handled here.
        jdbcTemplate.update(
                "UPDATE messages SET content = ? WHERE conversation_id = ?",
                "not-valid-base64-ciphertext!!!",
                bobConversationId);
        // The raw JDBC update above bypasses Hibernate entirely, so the
        // already-loaded Message stays cached (with its original, correctly
        // decrypted content) in this transaction's persistence context -
        // clear it so the chat list's query actually re-reads and
        // re-decrypts the now-corrupted row instead of returning stale data.
        entityManager.clear();

        MvcResult result = activeChats(alice.token)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(2)))
                .andReturn();

        var chats = jsonMapper.readTree(result.getResponse().getContentAsString());
        for (var chat : chats) {
            String otherUsername = chat.get("otherUser").get("username").asString();
            if (otherUsername.equals("bob_chat_baddecrypt")) {
                assertTrue(chat.get("lastMessage").isNull(), "the corrupted conversation must fall back to no preview");
            } else {
                assertEquals("a perfectly normal message", chat.get("lastMessage").get("content").asString());
            }
        }
    }

    // ---- sorting ----

    @Test
    void activeChatsAreSortedByMostRecentActivityDescending() throws Exception {
        RegisteredUser alice = register("alice_chat_sort", "alice.chat.sort@example.com");
        RegisteredUser bob = register("bob_chat_sort", "bob.chat.sort@example.com");
        RegisteredUser carol = register("carol_chat_sort", "carol.chat.sort@example.com");

        becomeContacts(alice, bob);
        becomeContacts(alice, carol);

        UUID bobConversationId = directConversationId(alice.id, bob.id);
        UUID carolConversationId = directConversationId(alice.id, carol.id);

        Instant now = Instant.now();
        setLastActivity(bobConversationId, now.minus(1, ChronoUnit.HOURS));
        setLastActivity(carolConversationId, now);

        activeChats(alice.token)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(2)))
                .andExpect(jsonPath("$[0].otherUser.username").value("carol_chat_sort"))
                .andExpect(jsonPath("$[1].otherUser.username").value("bob_chat_sort"));

        // Flip which conversation is most recent - ordering must follow.
        setLastActivity(bobConversationId, now.plus(1, ChronoUnit.HOURS));

        activeChats(alice.token)
                .andExpect(jsonPath("$[0].otherUser.username").value("bob_chat_sort"))
                .andExpect(jsonPath("$[1].otherUser.username").value("carol_chat_sort"));
    }

    // ---- archive ----

    @Test
    void participantCanArchiveChat() throws Exception {
        RegisteredUser alice = register("alice_chat_arch", "alice.chat.arch@example.com");
        RegisteredUser bob = register("bob_chat_arch", "bob.chat.arch@example.com");
        becomeContacts(alice, bob);
        UUID conversationId = directConversationId(alice.id, bob.id);

        archiveChat(alice.token, conversationId)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.archived").value(true));
    }

    @Test
    void archivedChatDisappearsFromActiveListAndAppearsInArchivedList() throws Exception {
        RegisteredUser alice = register("alice_chat_move", "alice.chat.move@example.com");
        RegisteredUser bob = register("bob_chat_move", "bob.chat.move@example.com");
        becomeContacts(alice, bob);
        UUID conversationId = directConversationId(alice.id, bob.id);

        archiveChat(alice.token, conversationId).andExpect(status().isOk());

        activeChats(alice.token).andExpect(jsonPath("$", hasSize(0)));
        archivedChats(alice.token)
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].otherUser.username").value("bob_chat_move"))
                .andExpect(jsonPath("$[0].archived").value(true));
    }

    @Test
    void archivingForOneUserDoesNotArchiveForTheOther() throws Exception {
        RegisteredUser alice = register("alice_chat_solo", "alice.chat.solo@example.com");
        RegisteredUser bob = register("bob_chat_solo", "bob.chat.solo@example.com");
        becomeContacts(alice, bob);
        UUID conversationId = directConversationId(alice.id, bob.id);

        archiveChat(alice.token, conversationId).andExpect(status().isOk());

        activeChats(alice.token).andExpect(jsonPath("$", hasSize(0)));
        activeChats(bob.token).andExpect(jsonPath("$", hasSize(1)));
        archivedChats(bob.token).andExpect(jsonPath("$", hasSize(0)));
    }

    @Test
    void unrelatedUserCannotArchiveChat() throws Exception {
        RegisteredUser alice = register("alice_chat_noarch", "alice.chat.noarch@example.com");
        RegisteredUser bob = register("bob_chat_noarch", "bob.chat.noarch@example.com");
        RegisteredUser carol = register("carol_chat_noarch", "carol.chat.noarch@example.com");
        becomeContacts(alice, bob);
        UUID conversationId = directConversationId(alice.id, bob.id);

        archiveChat(carol.token, conversationId).andExpect(status().isNotFound());

        // Neither original participant's state should have changed.
        activeChats(alice.token).andExpect(jsonPath("$", hasSize(1)));
        activeChats(bob.token).andExpect(jsonPath("$", hasSize(1)));
    }

    @Test
    void archivingInvalidChatIdIsHandledSafely() throws Exception {
        RegisteredUser alice = register("alice_chat_badid", "alice.chat.badid@example.com");

        archiveChat(alice.token, UUID.randomUUID()).andExpect(status().isNotFound());
    }

    @Test
    void archivingRequiresAuthentication() throws Exception {
        mockMvc.perform(post("/api/chats/" + UUID.randomUUID() + "/archive")).andExpect(status().isUnauthorized());
    }

    @Test
    void archivingIsIdempotent() throws Exception {
        RegisteredUser alice = register("alice_chat_archidem", "alice.chat.archidem@example.com");
        RegisteredUser bob = register("bob_chat_archidem", "bob.chat.archidem@example.com");
        becomeContacts(alice, bob);
        UUID conversationId = directConversationId(alice.id, bob.id);

        archiveChat(alice.token, conversationId).andExpect(status().isOk());
        archiveChat(alice.token, conversationId)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.archived").value(true));

        archivedChats(alice.token).andExpect(jsonPath("$", hasSize(1)));
    }

    // ---- unarchive ----

    @Test
    void participantCanUnarchiveChat() throws Exception {
        RegisteredUser alice = register("alice_chat_unarch", "alice.chat.unarch@example.com");
        RegisteredUser bob = register("bob_chat_unarch", "bob.chat.unarch@example.com");
        becomeContacts(alice, bob);
        UUID conversationId = directConversationId(alice.id, bob.id);
        archiveChat(alice.token, conversationId).andExpect(status().isOk());

        unarchiveChat(alice.token, conversationId)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.archived").value(false));

        activeChats(alice.token).andExpect(jsonPath("$", hasSize(1)));
        archivedChats(alice.token).andExpect(jsonPath("$", hasSize(0)));
    }

    @Test
    void unrelatedUserCannotUnarchiveChat() throws Exception {
        RegisteredUser alice = register("alice_chat_nounarch", "alice.chat.nounarch@example.com");
        RegisteredUser bob = register("bob_chat_nounarch", "bob.chat.nounarch@example.com");
        RegisteredUser carol = register("carol_chat_nounarch", "carol.chat.nounarch@example.com");
        becomeContacts(alice, bob);
        UUID conversationId = directConversationId(alice.id, bob.id);
        archiveChat(alice.token, conversationId).andExpect(status().isOk());

        unarchiveChat(carol.token, conversationId).andExpect(status().isNotFound());

        archivedChats(alice.token).andExpect(jsonPath("$", hasSize(1)));
    }

    @Test
    void repeatedUnarchiveRemainsSafe() throws Exception {
        RegisteredUser alice = register("alice_chat_unarchidem", "alice.chat.unarchidem@example.com");
        RegisteredUser bob = register("bob_chat_unarchidem", "bob.chat.unarchidem@example.com");
        becomeContacts(alice, bob);
        UUID conversationId = directConversationId(alice.id, bob.id);
        archiveChat(alice.token, conversationId).andExpect(status().isOk());

        unarchiveChat(alice.token, conversationId).andExpect(status().isOk());
        unarchiveChat(alice.token, conversationId)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.archived").value(false));

        activeChats(alice.token).andExpect(jsonPath("$", hasSize(1)));
    }

    // ---- persistence ----

    @Test
    void archiveStateIsPersistedPerParticipant() throws Exception {
        RegisteredUser alice = register("alice_chat_persist", "alice.chat.persist@example.com");
        RegisteredUser bob = register("bob_chat_persist", "bob.chat.persist@example.com");
        becomeContacts(alice, bob);
        UUID conversationId = directConversationId(alice.id, bob.id);

        archiveChat(alice.token, conversationId).andExpect(status().isOk());

        var aliceMembership = participantRepository.findByConversationIdAndUserId(conversationId, alice.id).orElseThrow();
        var bobMembership = participantRepository.findByConversationIdAndUserId(conversationId, bob.id).orElseThrow();

        assertTrue(aliceMembership.isArchived());
        assertNotNull(aliceMembership.getArchivedAt());
        assertFalse(bobMembership.isArchived());
        assertNull(bobMembership.getArchivedAt());
    }

    // ---- unread count ----

    @Test
    void chatListReportsUnreadCountForReceivedMessages() throws Exception {
        RegisteredUser alice = register("alice_chat_unread", "alice.chat.unread@example.com");
        RegisteredUser bob = register("bob_chat_unread", "bob.chat.unread@example.com");
        becomeContacts(alice, bob);
        UUID chatId = directConversationId(alice.id, bob.id);

        sendMessage(alice.token, chatId, "one").andExpect(status().isCreated());
        sendMessage(alice.token, chatId, "two").andExpect(status().isCreated());

        activeChats(bob.token)
                .andExpect(jsonPath("$[0].unreadCount").value(2));
        // The sender's own copy of the chat has nothing unread - both
        // messages are theirs, not something they've yet to read.
        activeChats(alice.token)
                .andExpect(jsonPath("$[0].unreadCount").value(0));
    }

    @Test
    void markingMessagesReadClearsTheUnreadCount() throws Exception {
        RegisteredUser alice = register("alice_chat_unreadclr", "alice.chat.unreadclr@example.com");
        RegisteredUser bob = register("bob_chat_unreadclr", "bob.chat.unreadclr@example.com");
        becomeContacts(alice, bob);
        UUID chatId = directConversationId(alice.id, bob.id);

        sendMessage(alice.token, chatId, "one").andExpect(status().isCreated());
        sendMessage(alice.token, chatId, "two").andExpect(status().isCreated());
        activeChats(bob.token).andExpect(jsonPath("$[0].unreadCount").value(2));

        mockMvc.perform(post("/api/chats/" + chatId + "/messages/read")
                        .header("Authorization", "Bearer " + bob.token))
                .andExpect(status().isNoContent());

        activeChats(bob.token).andExpect(jsonPath("$[0].unreadCount").value(0));
    }

    @Test
    void unreadCountIsZeroForAChatWithNoMessages() throws Exception {
        RegisteredUser alice = register("alice_chat_unreadnone", "alice.chat.unreadnone@example.com");
        RegisteredUser bob = register("bob_chat_unreadnone", "bob.chat.unreadnone@example.com");
        becomeContacts(alice, bob);

        activeChats(alice.token).andExpect(jsonPath("$[0].unreadCount").value(0));
    }

    // ---- helpers ----

    private ResultActions sendMessage(String token, UUID chatId, String content) throws Exception {
        return mockMvc.perform(post("/api/chats/" + chatId + "/messages")
                .contentType(MediaType.APPLICATION_JSON)
                .content(jsonMapper.writeValueAsString(new SendMessagePayload(content)))
                .header("Authorization", "Bearer " + token));
    }

    private void becomeContacts(RegisteredUser sender, RegisteredUser recipient) throws Exception {
        UUID invitationId = sendInvitationAndGetId(sender.token, recipient.id);
        mockMvc.perform(post("/api/contacts/invitations/" + invitationId + "/accept")
                        .header("Authorization", "Bearer " + recipient.token))
                .andExpect(status().isOk());
    }

    private UUID directConversationId(UUID userA, UUID userB) {
        boolean aIsLower = userA.toString().compareTo(userB.toString()) < 0;
        UUID low = aIsLower ? userA : userB;
        UUID high = aIsLower ? userB : userA;
        return conversationRepository.findByDirectUserAIdAndDirectUserBId(low, high).orElseThrow().getId();
    }

    private void setLastActivity(UUID conversationId, Instant instant) {
        Conversation conversation = conversationRepository.findById(conversationId).orElseThrow();
        conversation.touchActivity(instant);
        conversationRepository.saveAndFlush(conversation);
    }

    private ResultActions activeChats(String token) throws Exception {
        return mockMvc.perform(get("/api/chats").header("Authorization", "Bearer " + token));
    }

    private ResultActions archivedChats(String token) throws Exception {
        return mockMvc.perform(get("/api/chats/archived").header("Authorization", "Bearer " + token));
    }

    private ResultActions archiveChat(String token, UUID conversationId) throws Exception {
        return mockMvc.perform(
                post("/api/chats/" + conversationId + "/archive").header("Authorization", "Bearer " + token));
    }

    private ResultActions unarchiveChat(String token, UUID conversationId) throws Exception {
        return mockMvc.perform(
                post("/api/chats/" + conversationId + "/unarchive").header("Authorization", "Bearer " + token));
    }

    private UUID sendInvitationAndGetId(String senderToken, UUID recipientId) throws Exception {
        String body = jsonMapper.writeValueAsString(new SendInvitationPayload(recipientId));
        MockHttpServletRequestBuilder request = post("/api/contacts/invitations")
                .contentType(MediaType.APPLICATION_JSON)
                .content(body)
                .header("Authorization", "Bearer " + senderToken);
        MvcResult result = mockMvc.perform(request).andExpect(status().isCreated()).andReturn();
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

    private record SendMessagePayload(String content) {
    }
}
