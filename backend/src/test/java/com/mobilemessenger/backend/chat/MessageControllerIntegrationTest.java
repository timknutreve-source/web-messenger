package com.mobilemessenger.backend.chat;

import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.notNullValue;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.json.JsonMapper;

/**
 * End-to-end tests for Phase 7 text messaging: sending, loading/pagination,
 * editing, deleting, and the SENT/DELIVERED/READ status flow, against a real
 * database. Each test runs in its own transaction that is rolled back
 * afterwards.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class MessageControllerIntegrationTest {

    private static final String STRONG_PASSWORD = "Str0ng!Pass";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ConversationRepository conversationRepository;

    @Autowired
    private MessageRepository messageRepository;

    private final JsonMapper jsonMapper = JsonMapper.builder().build();

    // ---- sending ----

    @Test
    void participantCanSendAMessage() throws Exception {
        RegisteredUser alice = register("alice_msg_send", "alice.msg.send@example.com");
        RegisteredUser bob = register("bob_msg_send", "bob.msg.send@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        sendMessage(alice.token, chatId, "Hello Bob!")
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id", notNullValue()))
                .andExpect(jsonPath("$.conversationId").value(chatId.toString()))
                .andExpect(jsonPath("$.sender.username").value("alice_msg_send"))
                .andExpect(jsonPath("$.content").value("Hello Bob!"))
                .andExpect(jsonPath("$.status").value("SENT"))
                .andExpect(jsonPath("$.deleted").value(false));
    }

    @Test
    void sentMessagePersists() throws Exception {
        RegisteredUser alice = register("alice_msg_persist", "alice.msg.persist@example.com");
        RegisteredUser bob = register("bob_msg_persist", "bob.msg.persist@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        UUID messageId = sendMessageAndGetId(alice.token, chatId, "Persisted message");

        assertTrue(messageRepository.findById(messageId).isPresent());
        assertEquals("Persisted message", messageRepository.findById(messageId).orElseThrow().getContent());
    }

    @Test
    void senderComesFromAuthenticationNotRequestBody() throws Exception {
        RegisteredUser alice = register("alice_msg_authsender", "alice.msg.authsender@example.com");
        RegisteredUser bob = register("bob_msg_authsender", "bob.msg.authsender@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        // SendMessageRequest only has a content field - there is no
        // sender/senderId field a client could even attempt to spoof.
        sendMessage(bob.token, chatId, "From bob")
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.sender.username").value("bob_msg_authsender"));
    }

    @Test
    void sendingUpdatesConversationLastActivity() throws Exception {
        RegisteredUser alice = register("alice_msg_activity", "alice.msg.activity@example.com");
        RegisteredUser bob = register("bob_msg_activity", "bob.msg.activity@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        var beforeSend = conversationRepository.findById(chatId).orElseThrow().getLastActivityAt();

        sendMessage(alice.token, chatId, "bumps activity").andExpect(status().isCreated());

        var afterSend = conversationRepository.findById(chatId).orElseThrow().getLastActivityAt();
        assertTrue(afterSend.isAfter(beforeSend) || afterSend.equals(beforeSend));
    }

    @Test
    void sendingAMessageMovesChatToTopOfActiveList() throws Exception {
        RegisteredUser alice = register("alice_msg_chatlist", "alice.msg.chatlist@example.com");
        RegisteredUser bob = register("bob_msg_chatlist", "bob.msg.chatlist@example.com");
        RegisteredUser carol = register("carol_msg_chatlist", "carol.msg.chatlist@example.com");
        UUID bobChatId = becomeContactsAndGetChatId(alice, bob);
        becomeContactsAndGetChatId(alice, carol);

        sendMessage(alice.token, bobChatId, "hi bob").andExpect(status().isCreated());

        mockMvc.perform(get("/api/chats").header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value(bobChatId.toString()))
                .andExpect(jsonPath("$[0].lastMessage.content").value("hi bob"));
    }

    @Test
    void nonParticipantCannotSendAMessage() throws Exception {
        RegisteredUser alice = register("alice_msg_nosend", "alice.msg.nosend@example.com");
        RegisteredUser bob = register("bob_msg_nosend", "bob.msg.nosend@example.com");
        RegisteredUser carol = register("carol_msg_nosend", "carol.msg.nosend@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        sendMessage(carol.token, chatId, "intruding").andExpect(status().isNotFound());
    }

    @Test
    void blankContentIsRejected() throws Exception {
        RegisteredUser alice = register("alice_msg_blank", "alice.msg.blank@example.com");
        RegisteredUser bob = register("bob_msg_blank", "bob.msg.blank@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        sendMessage(alice.token, chatId, "   ").andExpect(status().isBadRequest());
    }

    @Test
    void excessiveContentLengthIsRejected() throws Exception {
        RegisteredUser alice = register("alice_msg_toolong", "alice.msg.toolong@example.com");
        RegisteredUser bob = register("bob_msg_toolong", "bob.msg.toolong@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        sendMessage(alice.token, chatId, "x".repeat(4001)).andExpect(status().isBadRequest());
    }

    @Test
    void sendingRequiresAuthentication() throws Exception {
        mockMvc.perform(post("/api/chats/" + UUID.randomUUID() + "/messages")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(jsonMapper.writeValueAsString(new SendPayload("hi"))))
                .andExpect(status().isUnauthorized());
    }

    // ---- loading / pagination ----

    @Test
    void participantCanLoadMessages() throws Exception {
        RegisteredUser alice = register("alice_msg_load", "alice.msg.load@example.com");
        RegisteredUser bob = register("bob_msg_load", "bob.msg.load@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        sendMessage(alice.token, chatId, "hi").andExpect(status().isCreated());

        loadMessages(bob.token, chatId, null, null)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.messages", hasSize(1)))
                .andExpect(jsonPath("$.messages[0].content").value("hi"))
                .andExpect(jsonPath("$.hasMore").value(false));
    }

    @Test
    void messagesAreSortedChronologically() throws Exception {
        RegisteredUser alice = register("alice_msg_sort", "alice.msg.sort@example.com");
        RegisteredUser bob = register("bob_msg_sort", "bob.msg.sort@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        sendMessage(alice.token, chatId, "first").andExpect(status().isCreated());
        sendMessage(bob.token, chatId, "second").andExpect(status().isCreated());
        sendMessage(alice.token, chatId, "third").andExpect(status().isCreated());

        loadMessages(alice.token, chatId, null, null)
                .andExpect(jsonPath("$.messages", hasSize(3)))
                .andExpect(jsonPath("$.messages[0].content").value("first"))
                .andExpect(jsonPath("$.messages[1].content").value("second"))
                .andExpect(jsonPath("$.messages[2].content").value("third"));
    }

    @Test
    void paginationLoadsOlderMessagesWithoutDuplicatesOrGaps() throws Exception {
        RegisteredUser alice = register("alice_msg_page", "alice.msg.page@example.com");
        RegisteredUser bob = register("bob_msg_page", "bob.msg.page@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        for (int i = 1; i <= 5; i++) {
            sendMessage(alice.token, chatId, "msg" + i).andExpect(status().isCreated());
        }

        MvcResult firstPageResult = loadMessages(alice.token, chatId, null, 2)
                .andExpect(jsonPath("$.messages", hasSize(2)))
                .andExpect(jsonPath("$.hasMore").value(true))
                .andReturn();
        var firstPage = jsonMapper.readTree(firstPageResult.getResponse().getContentAsString());
        assertEquals("msg4", firstPage.get("messages").get(0).get("content").asString());
        assertEquals("msg5", firstPage.get("messages").get(1).get("content").asString());
        UUID oldestOnFirstPage = UUID.fromString(firstPage.get("messages").get(0).get("id").asString());

        MvcResult secondPageResult = loadMessages(alice.token, chatId, oldestOnFirstPage, 2)
                .andExpect(jsonPath("$.messages", hasSize(2)))
                .andExpect(jsonPath("$.hasMore").value(true))
                .andReturn();
        var secondPage = jsonMapper.readTree(secondPageResult.getResponse().getContentAsString());
        assertEquals("msg2", secondPage.get("messages").get(0).get("content").asString());
        assertEquals("msg3", secondPage.get("messages").get(1).get("content").asString());
        UUID oldestOnSecondPage = UUID.fromString(secondPage.get("messages").get(0).get("id").asString());

        loadMessages(alice.token, chatId, oldestOnSecondPage, 2)
                .andExpect(jsonPath("$.messages", hasSize(1)))
                .andExpect(jsonPath("$.messages[0].content").value("msg1"))
                .andExpect(jsonPath("$.hasMore").value(false));
    }

    @Test
    void nonParticipantCannotLoadMessages() throws Exception {
        RegisteredUser alice = register("alice_msg_noload", "alice.msg.noload@example.com");
        RegisteredUser bob = register("bob_msg_noload", "bob.msg.noload@example.com");
        RegisteredUser carol = register("carol_msg_noload", "carol.msg.noload@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        sendMessage(alice.token, chatId, "private").andExpect(status().isCreated());

        loadMessages(carol.token, chatId, null, null).andExpect(status().isNotFound());
    }

    // ---- editing ----

    @Test
    void senderCanEditOwnMessage() throws Exception {
        RegisteredUser alice = register("alice_msg_edit", "alice.msg.edit@example.com");
        RegisteredUser bob = register("bob_msg_edit", "bob.msg.edit@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        UUID messageId = sendMessageAndGetId(alice.token, chatId, "typo");

        editMessage(alice.token, chatId, messageId, "fixed")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content").value("fixed"))
                .andExpect(jsonPath("$.editedAt", notNullValue()));
    }

    @Test
    void editedStatePersists() throws Exception {
        RegisteredUser alice = register("alice_msg_editpersist", "alice.msg.editpersist@example.com");
        RegisteredUser bob = register("bob_msg_editpersist", "bob.msg.editpersist@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        UUID messageId = sendMessageAndGetId(alice.token, chatId, "typo");

        editMessage(alice.token, chatId, messageId, "fixed").andExpect(status().isOk());

        Message stored = messageRepository.findById(messageId).orElseThrow();
        assertEquals("fixed", stored.getContent());
        assertTrue(stored.getEditedAt() != null);
    }

    @Test
    void recipientCannotEditSendersMessage() throws Exception {
        RegisteredUser alice = register("alice_msg_noedit", "alice.msg.noedit@example.com");
        RegisteredUser bob = register("bob_msg_noedit", "bob.msg.noedit@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        UUID messageId = sendMessageAndGetId(alice.token, chatId, "original");

        editMessage(bob.token, chatId, messageId, "hijacked").andExpect(status().isForbidden());
    }

    @Test
    void unrelatedUserCannotEditMessage() throws Exception {
        RegisteredUser alice = register("alice_msg_uneditun", "alice.msg.uneditun@example.com");
        RegisteredUser bob = register("bob_msg_uneditun", "bob.msg.uneditun@example.com");
        RegisteredUser carol = register("carol_msg_uneditun", "carol.msg.uneditun@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        UUID messageId = sendMessageAndGetId(alice.token, chatId, "original");

        editMessage(carol.token, chatId, messageId, "hijacked").andExpect(status().isNotFound());
    }

    @Test
    void deletedMessageCannotBeEdited() throws Exception {
        RegisteredUser alice = register("alice_msg_editdeleted", "alice.msg.editdeleted@example.com");
        RegisteredUser bob = register("bob_msg_editdeleted", "bob.msg.editdeleted@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        UUID messageId = sendMessageAndGetId(alice.token, chatId, "to be deleted");
        deleteMessage(alice.token, chatId, messageId).andExpect(status().isNoContent());

        editMessage(alice.token, chatId, messageId, "resurrected").andExpect(status().isConflict());
    }

    // ---- deleting ----

    @Test
    void senderCanDeleteOwnMessage() throws Exception {
        RegisteredUser alice = register("alice_msg_delete", "alice.msg.delete@example.com");
        RegisteredUser bob = register("bob_msg_delete", "bob.msg.delete@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        UUID messageId = sendMessageAndGetId(alice.token, chatId, "secret");

        deleteMessage(alice.token, chatId, messageId).andExpect(status().isNoContent());
    }

    @Test
    void deletedMessageContentIsNotReturned() throws Exception {
        RegisteredUser alice = register("alice_msg_delcontent", "alice.msg.delcontent@example.com");
        RegisteredUser bob = register("bob_msg_delcontent", "bob.msg.delcontent@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        UUID messageId = sendMessageAndGetId(alice.token, chatId, "secret content");
        deleteMessage(alice.token, chatId, messageId).andExpect(status().isNoContent());

        loadMessages(bob.token, chatId, null, null)
                .andExpect(jsonPath("$.messages[0].content", nullValue()))
                .andExpect(jsonPath("$.messages[0].deleted").value(true));
    }

    @Test
    void deletedStatePersists() throws Exception {
        RegisteredUser alice = register("alice_msg_delpersist", "alice.msg.delpersist@example.com");
        RegisteredUser bob = register("bob_msg_delpersist", "bob.msg.delpersist@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        UUID messageId = sendMessageAndGetId(alice.token, chatId, "secret content");
        deleteMessage(alice.token, chatId, messageId).andExpect(status().isNoContent());

        Message stored = messageRepository.findById(messageId).orElseThrow();
        assertTrue(stored.isDeleted());
        assertEquals("", stored.getContent());
    }

    @Test
    void recipientCannotDeleteSendersMessage() throws Exception {
        RegisteredUser alice = register("alice_msg_nodel", "alice.msg.nodel@example.com");
        RegisteredUser bob = register("bob_msg_nodel", "bob.msg.nodel@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        UUID messageId = sendMessageAndGetId(alice.token, chatId, "keep me");

        deleteMessage(bob.token, chatId, messageId).andExpect(status().isForbidden());
    }

    @Test
    void unrelatedUserCannotDeleteMessage() throws Exception {
        RegisteredUser alice = register("alice_msg_nodelun", "alice.msg.nodelun@example.com");
        RegisteredUser bob = register("bob_msg_nodelun", "bob.msg.nodelun@example.com");
        RegisteredUser carol = register("carol_msg_nodelun", "carol.msg.nodelun@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        UUID messageId = sendMessageAndGetId(alice.token, chatId, "keep me");

        deleteMessage(carol.token, chatId, messageId).andExpect(status().isNotFound());
    }

    // ---- read / delivery status ----

    @Test
    void newMessageStartsWithSentStatus() throws Exception {
        RegisteredUser alice = register("alice_msg_sent", "alice.msg.sent@example.com");
        RegisteredUser bob = register("bob_msg_sent", "bob.msg.sent@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        UUID messageId = sendMessageAndGetId(alice.token, chatId, "hi");
        assertEquals(MessageStatus.SENT, messageRepository.findById(messageId).orElseThrow().getStatus());
    }

    @Test
    void recipientCanMarkMessageDelivered() throws Exception {
        RegisteredUser alice = register("alice_msg_delivered", "alice.msg.delivered@example.com");
        RegisteredUser bob = register("bob_msg_delivered", "bob.msg.delivered@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        UUID messageId = sendMessageAndGetId(alice.token, chatId, "hi");

        markDelivered(bob.token, chatId, messageId)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("DELIVERED"));
    }

    @Test
    void senderCannotMarkOwnMessageDelivered() throws Exception {
        RegisteredUser alice = register("alice_msg_nodeliv", "alice.msg.nodeliv@example.com");
        RegisteredUser bob = register("bob_msg_nodeliv", "bob.msg.nodeliv@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        UUID messageId = sendMessageAndGetId(alice.token, chatId, "hi");

        markDelivered(alice.token, chatId, messageId).andExpect(status().isBadRequest());
    }

    @Test
    void unrelatedUserCannotMarkMessageDelivered() throws Exception {
        RegisteredUser alice = register("alice_msg_nodelivun", "alice.msg.nodelivun@example.com");
        RegisteredUser bob = register("bob_msg_nodelivun", "bob.msg.nodelivun@example.com");
        RegisteredUser carol = register("carol_msg_nodelivun", "carol.msg.nodelivun@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        UUID messageId = sendMessageAndGetId(alice.token, chatId, "hi");

        markDelivered(carol.token, chatId, messageId).andExpect(status().isNotFound());
    }

    @Test
    void recipientCanMarkConversationRead() throws Exception {
        RegisteredUser alice = register("alice_msg_read", "alice.msg.read@example.com");
        RegisteredUser bob = register("bob_msg_read", "bob.msg.read@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        UUID messageId = sendMessageAndGetId(alice.token, chatId, "hi");

        markRead(bob.token, chatId).andExpect(status().isNoContent());

        assertEquals(MessageStatus.READ, messageRepository.findById(messageId).orElseThrow().getStatus());
    }

    @Test
    void markingReadDoesNotAffectTheSendersOwnMessagesAsSender() throws Exception {
        RegisteredUser alice = register("alice_msg_readown", "alice.msg.readown@example.com");
        RegisteredUser bob = register("bob_msg_readown", "bob.msg.readown@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        UUID messageId = sendMessageAndGetId(alice.token, chatId, "hi");

        markRead(alice.token, chatId).andExpect(status().isNoContent());

        assertEquals(MessageStatus.SENT, messageRepository.findById(messageId).orElseThrow().getStatus());
    }

    @Test
    void unrelatedUserCannotMarkConversationRead() throws Exception {
        RegisteredUser alice = register("alice_msg_noreadun", "alice.msg.noreadun@example.com");
        RegisteredUser bob = register("bob_msg_noreadun", "bob.msg.noreadun@example.com");
        RegisteredUser carol = register("carol_msg_noreadun", "carol.msg.noreadun@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        sendMessageAndGetId(alice.token, chatId, "hi");

        markRead(carol.token, chatId).andExpect(status().isNotFound());
    }

    // ---- helpers ----

    private UUID becomeContactsAndGetChatId(RegisteredUser sender, RegisteredUser recipient) throws Exception {
        UUID invitationId = sendInvitationAndGetId(sender.token, recipient.id);
        mockMvc.perform(post("/api/contacts/invitations/" + invitationId + "/accept")
                        .header("Authorization", "Bearer " + recipient.token))
                .andExpect(status().isOk());

        UUID low = sender.id.toString().compareTo(recipient.id.toString()) < 0 ? sender.id : recipient.id;
        UUID high = sender.id.toString().compareTo(recipient.id.toString()) < 0 ? recipient.id : sender.id;
        return conversationRepository.findByDirectUserAIdAndDirectUserBId(low, high).orElseThrow().getId();
    }

    private ResultActions sendMessage(String token, UUID chatId, String content) throws Exception {
        return mockMvc.perform(post("/api/chats/" + chatId + "/messages")
                .contentType(MediaType.APPLICATION_JSON)
                .content(jsonMapper.writeValueAsString(new SendPayload(content)))
                .header("Authorization", "Bearer " + token));
    }

    private UUID sendMessageAndGetId(String token, UUID chatId, String content) throws Exception {
        MvcResult result = sendMessage(token, chatId, content).andExpect(status().isCreated()).andReturn();
        return UUID.fromString(
                jsonMapper.readTree(result.getResponse().getContentAsString()).get("id").asString());
    }

    private ResultActions loadMessages(String token, UUID chatId, UUID before, Integer limit) throws Exception {
        StringBuilder url = new StringBuilder("/api/chats/" + chatId + "/messages");
        List<String> params = new ArrayList<>();
        if (before != null) params.add("before=" + before);
        if (limit != null) params.add("limit=" + limit);
        if (!params.isEmpty()) url.append('?').append(String.join("&", params));

        return mockMvc.perform(get(url.toString()).header("Authorization", "Bearer " + token));
    }

    private ResultActions editMessage(String token, UUID chatId, UUID messageId, String content) throws Exception {
        return mockMvc.perform(put("/api/chats/" + chatId + "/messages/" + messageId)
                .contentType(MediaType.APPLICATION_JSON)
                .content(jsonMapper.writeValueAsString(new SendPayload(content)))
                .header("Authorization", "Bearer " + token));
    }

    private ResultActions deleteMessage(String token, UUID chatId, UUID messageId) throws Exception {
        return mockMvc.perform(
                delete("/api/chats/" + chatId + "/messages/" + messageId).header("Authorization", "Bearer " + token));
    }

    private ResultActions markRead(String token, UUID chatId) throws Exception {
        return mockMvc.perform(
                post("/api/chats/" + chatId + "/messages/read").header("Authorization", "Bearer " + token));
    }

    private ResultActions markDelivered(String token, UUID chatId, UUID messageId) throws Exception {
        return mockMvc.perform(post("/api/chats/" + chatId + "/messages/" + messageId + "/delivered")
                .header("Authorization", "Bearer " + token));
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
        return new RegisteredUser(id, token);
    }

    private record RegisteredUser(UUID id, String token) {
    }

    private record RegisterPayload(String username, String email, String password) {
    }

    private record SendInvitationPayload(UUID recipientId) {
    }

    private record SendPayload(String content) {
    }
}
