package com.mobilemessenger.backend.chat;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.hasSize;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.mobilemessenger.backend.support.ApiTestSupport;
import com.mobilemessenger.backend.support.ApiTestSupport.TestUser;
import com.mobilemessenger.backend.user.UserRepository;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.JsonNode;

/**
 * Text search within one chat (individual or group): no match, one match,
 * many matches, case-insensitivity, and the rules that keep it scoped to
 * chats the caller belongs to and to messages that still exist.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class MessageSearchIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    private ApiTestSupport api;

    @BeforeEach
    void setUp() {
        api = new ApiTestSupport(mockMvc, userRepository);
    }

    private String uniq(String prefix) {
        return prefix + UUID.randomUUID().toString().substring(0, 6);
    }

    private List<String> search(TestUser viewer, UUID chatId, String query) throws Exception {
        JsonNode body = api.json(api.request("GET", "/api/chats/" + chatId + "/messages/search?q=" + query, viewer, null)
                .andExpect(status().isOk()));
        return api.ids(body.get("results"), "content");
    }

    @Test
    void findsNothingWhenNoMessageMatches() throws Exception {
        TestUser alice = api.user(uniq("sa"));
        TestUser bob = api.user(uniq("sb"));
        UUID chat = api.becomeContacts(alice, bob);
        api.sendMessage(alice, chat, "hello there");

        api.request("GET", "/api/chats/" + chat + "/messages/search?q=zebra", bob, null)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.results", hasSize(0)))
                .andExpect(jsonPath("$.truncated").value(false));
    }

    @Test
    void findsASingleMatchInAnIndividualChat() throws Exception {
        TestUser alice = api.user(uniq("sa"));
        TestUser bob = api.user(uniq("sb"));
        UUID chat = api.becomeContacts(alice, bob);
        api.sendMessage(alice, chat, "let's get pizza tonight");
        api.sendMessage(bob, chat, "sounds good");

        assertThat(search(bob, chat, "pizza")).containsExactly("let's get pizza tonight");
    }

    @Test
    void findsManyMatchesOldestFirstAndIsCaseInsensitive() throws Exception {
        TestUser alice = api.user(uniq("sa"));
        TestUser bob = api.user(uniq("sb"));
        UUID chat = api.becomeContacts(alice, bob);
        api.sendMessage(alice, chat, "Meeting at nine");
        api.sendMessage(bob, chat, "unrelated");
        api.sendMessage(bob, chat, "the MEETING moved");
        api.sendMessage(alice, chat, "ok, meeting confirmed");

        assertThat(search(alice, chat, "meeting"))
                .containsExactly("Meeting at nine", "the MEETING moved", "ok, meeting confirmed");
        assertThat(search(alice, chat, "MEETING")).hasSize(3);
    }

    @Test
    void searchWorksInAGroupChatAndFindsEveryMembersMessages() throws Exception {
        TestUser alice = api.user(uniq("sa"));
        TestUser bob = api.user(uniq("sb"));
        TestUser carol = api.user(uniq("sc"));
        UUID group = api.groupOf("Search group", alice, bob, carol);
        api.sendMessage(alice, group, "budget draft attached");
        api.sendMessage(carol, group, "thanks for the budget");
        api.sendMessage(bob, group, "lunch?");

        JsonNode body = api.json(api.request("GET", "/api/chats/" + group + "/messages/search?q=budget", bob, null)
                .andExpect(status().isOk()));
        assertThat(body.get("results")).hasSize(2);
        assertThat(body.get("results").get(0).get("sender").get("username").asString()).isEqualTo(alice.username());
        assertThat(body.get("results").get(1).get("sender").get("username").asString()).isEqualTo(carol.username());
    }

    @Test
    void searchOnlyLooksInsideTheRequestedChat() throws Exception {
        TestUser alice = api.user(uniq("sa"));
        TestUser bob = api.user(uniq("sb"));
        TestUser carol = api.user(uniq("sc"));
        UUID withBob = api.becomeContacts(alice, bob);
        UUID withCarol = api.becomeContacts(alice, carol);
        api.sendMessage(alice, withBob, "the password is hunter2");
        api.sendMessage(alice, withCarol, "nothing to see");

        assertThat(search(alice, withCarol, "hunter2")).isEmpty();
        assertThat(search(alice, withBob, "hunter2")).hasSize(1);
    }

    @Test
    void deletedMessagesAreNeverFound() throws Exception {
        TestUser alice = api.user(uniq("sa"));
        TestUser bob = api.user(uniq("sb"));
        UUID chat = api.becomeContacts(alice, bob);
        String id = api.sendMessage(alice, chat, "oops wrong chat").get("id").asString();
        assertThat(search(bob, chat, "oops")).hasSize(1);

        api.request("DELETE", "/api/chats/" + chat + "/messages/" + id, alice, null).andExpect(status().isNoContent());

        assertThat(search(bob, chat, "oops")).isEmpty();
    }

    @Test
    void anEditedMessageIsFoundByItsNewTextNotItsOldText() throws Exception {
        TestUser alice = api.user(uniq("sa"));
        TestUser bob = api.user(uniq("sb"));
        UUID chat = api.becomeContacts(alice, bob);
        String id = api.sendMessage(alice, chat, "see you at 5").get("id").asString();
        api.request("PUT", "/api/chats/" + chat + "/messages/" + id, alice, java.util.Map.of("content", "see you at 6"))
                .andExpect(status().isOk());

        assertThat(search(bob, chat, "at 5")).isEmpty();
        assertThat(search(bob, chat, "at 6")).hasSize(1);
    }

    @Test
    void searchDoesNotChangeTheChatItself() throws Exception {
        TestUser alice = api.user(uniq("sa"));
        TestUser bob = api.user(uniq("sb"));
        UUID chat = api.becomeContacts(alice, bob);
        api.sendMessage(alice, chat, "find me");
        api.sendMessage(alice, chat, "and me");

        search(bob, chat, "find");

        // The search read nothing-but: the messages are still unread and the chat untouched.
        for (JsonNode summary : api.json(api.request("GET", "/api/chats", bob, null))) {
            if (summary.get("id").asString().equals(chat.toString())) {
                assertThat(summary.get("unreadCount").asInt()).isEqualTo(2);
            }
        }
        api.request("GET", "/api/chats/" + chat + "/messages", bob, null)
                .andExpect(jsonPath("$.messages", hasSize(2)));
    }

    @Test
    void aBlankOrTooLongQueryIsRejected() throws Exception {
        TestUser alice = api.user(uniq("sa"));
        TestUser bob = api.user(uniq("sb"));
        UUID chat = api.becomeContacts(alice, bob);

        api.request("GET", "/api/chats/" + chat + "/messages/search?q=  ", alice, null)
                .andExpect(status().isBadRequest());
        api.request("GET", "/api/chats/" + chat + "/messages/search?q=" + "x".repeat(101), alice, null)
                .andExpect(status().isBadRequest());
    }

    @Test
    void aNonParticipantCannotSearchAChat() throws Exception {
        TestUser alice = api.user(uniq("sa"));
        TestUser bob = api.user(uniq("sb"));
        TestUser outsider = api.user(uniq("so"));
        UUID chat = api.becomeContacts(alice, bob);
        api.sendMessage(alice, chat, "confidential");

        api.request("GET", "/api/chats/" + chat + "/messages/search?q=confidential", outsider, null)
                .andExpect(status().isNotFound());
        api.request("GET", "/api/chats/" + chat + "/messages/search?q=confidential", null, null)
                .andExpect(status().isUnauthorized());
    }

    @Test
    void anAlmostUnboundedNumberOfMatchesIsCappedAndFlaggedAsTruncated() throws Exception {
        TestUser alice = api.user(uniq("sa"));
        TestUser bob = api.user(uniq("sb"));
        UUID chat = api.becomeContacts(alice, bob);
        for (int i = 0; i < MessageService.MAX_SEARCH_RESULTS + 1; i++) {
            api.sendMessage(alice, chat, "echo " + i);
            Thread.sleep(2); // keep creation timestamps distinct so "most recent" is unambiguous
        }

        JsonNode body = api.json(api.request("GET", "/api/chats/" + chat + "/messages/search?q=echo", bob, null)
                .andExpect(status().isOk()));
        assertThat(body.get("results")).hasSize(MessageService.MAX_SEARCH_RESULTS);
        assertThat(body.get("truncated").asBoolean()).isTrue();
        // The most recent matches are the ones kept, still in chronological order.
        assertThat(body.get("results").get(MessageService.MAX_SEARCH_RESULTS - 1).get("content").asString())
                .isEqualTo("echo " + MessageService.MAX_SEARCH_RESULTS);
        assertThat(body.get("results").get(0).get("content").asString()).isEqualTo("echo 1");
    }
}
