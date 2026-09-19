package com.mobilemessenger.backend.chat.group;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.hasSize;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.mobilemessenger.backend.support.ApiTestSupport;
import com.mobilemessenger.backend.support.ApiTestSupport.TestUser;
import com.mobilemessenger.backend.user.UserRepository;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.JsonNode;

/**
 * Group chats end to end through the real HTTP API against a real database:
 * creating a group, inviting contacts, accepting/declining, membership,
 * group messaging, and the group-specific delivered/read/unread rules.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class GroupControllerIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    private ApiTestSupport api;

    @BeforeEach
    void setUp() {
        api = new ApiTestSupport(mockMvc, userRepository);
    }

    private String uniq(String prefix) {
        return prefix + UUID.randomUUID().toString().substring(0, 6);
    }

    // ---- creating a group ----

    @Test
    void creatingAGroupMakesTheCreatorItsAdminAndInvitesTheOthers() throws Exception {
        TestUser alice = api.user(uniq("ga"));
        TestUser bob = api.user(uniq("gb"));
        api.becomeContacts(alice, bob);

        api.request("POST", "/api/groups", alice, Map.of("name", "Weekend plans", "memberIds", List.of(bob.id().toString())))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.name").value("Weekend plans"))
                .andExpect(jsonPath("$.members", hasSize(1)))
                .andExpect(jsonPath("$.members[0].user.username").value(alice.username()))
                .andExpect(jsonPath("$.members[0].role").value("ADMIN"))
                .andExpect(jsonPath("$.pendingInvitees", hasSize(1)))
                .andExpect(jsonPath("$.pendingInvitees[0].username").value(bob.username()));
    }

    @Test
    void aNewGroupAppearsInTheCreatorsChatListAsAGroup() throws Exception {
        TestUser alice = api.user(uniq("ga"));
        TestUser bob = api.user(uniq("gb"));
        api.becomeContacts(alice, bob);
        api.request("POST", "/api/groups", alice, Map.of("name", "Book club", "memberIds", List.of(bob.id().toString())))
                .andExpect(status().isCreated());

        JsonNode chats = api.json(api.request("GET", "/api/chats", alice, null).andExpect(status().isOk()));
        JsonNode group = null;
        for (JsonNode chat : chats) {
            if ("GROUP".equals(chat.get("type").asString())) {
                group = chat;
            }
        }
        assertThat(group).isNotNull();
        assertThat(group.get("name").asString()).isEqualTo("Book club");
        assertThat(group.get("memberCount").asInt()).isEqualTo(1);
        assertThat(group.get("otherUser").isNull()).isTrue();
    }

    @Test
    void onlyYourOwnContactsCanBeInvited() throws Exception {
        TestUser alice = api.user(uniq("ga"));
        TestUser stranger = api.user(uniq("gs"));

        api.request("POST", "/api/groups", alice, Map.of("name", "Nope", "memberIds", List.of(stranger.id().toString())))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("You can only invite your own contacts"));
    }

    @Test
    void youCannotInviteYourselfOrCreateAGroupWithoutAnInvitee() throws Exception {
        TestUser alice = api.user(uniq("ga"));

        api.request("POST", "/api/groups", alice, Map.of("name", "Solo", "memberIds", List.of(alice.id().toString())))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("You can't invite yourself"));
        api.request("POST", "/api/groups", alice, Map.of("name", "Empty", "memberIds", List.of()))
                .andExpect(status().isBadRequest());
    }

    @Test
    void aGroupNeedsAName() throws Exception {
        TestUser alice = api.user(uniq("ga"));
        TestUser bob = api.user(uniq("gb"));
        api.becomeContacts(alice, bob);

        api.request("POST", "/api/groups", alice, Map.of("name", "   ", "memberIds", List.of(bob.id().toString())))
                .andExpect(status().isBadRequest());
    }

    @Test
    void creatingAGroupRequiresAuthentication() throws Exception {
        api.request("POST", "/api/groups", null, Map.of("name", "x", "memberIds", List.of(UUID.randomUUID().toString())))
                .andExpect(status().isUnauthorized());
    }

    // ---- invitations ----

    @Test
    void anInviteeSeesThePendingInvitationAndCanAcceptIt() throws Exception {
        TestUser alice = api.user(uniq("ga"));
        TestUser bob = api.user(uniq("gb"));
        api.becomeContacts(alice, bob);
        JsonNode group = api.json(api.request("POST", "/api/groups", alice,
                        Map.of("name", "Trip", "memberIds", List.of(bob.id().toString())))
                .andExpect(status().isCreated()));

        JsonNode pending = api.json(api.request("GET", "/api/groups/invitations/pending", bob, null)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].groupName").value("Trip"))
                .andExpect(jsonPath("$[0].inviter.username").value(alice.username())));

        api.request("POST", "/api/groups/invitations/" + pending.get(0).get("id").asString() + "/accept", bob, null)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.members", hasSize(2)))
                .andExpect(jsonPath("$.pendingInvitees", hasSize(0)));

        // Now a member: the group is in his chat list, and nothing is pending any more.
        assertThat(api.ids(api.json(api.request("GET", "/api/chats", bob, null)), "id"))
                .contains(group.get("id").asString());
        api.request("GET", "/api/groups/invitations/pending", bob, null).andExpect(jsonPath("$", hasSize(0)));
    }

    @Test
    void declining_doesNotMakeSomeoneAMemberAndTheyCanBeInvitedAgain() throws Exception {
        TestUser alice = api.user(uniq("ga"));
        TestUser bob = api.user(uniq("gb"));
        api.becomeContacts(alice, bob);
        JsonNode group = api.json(api.request("POST", "/api/groups", alice,
                        Map.of("name", "Decline me", "memberIds", List.of(bob.id().toString())))
                .andExpect(status().isCreated()));
        String groupId = group.get("id").asString();
        JsonNode pending = api.json(api.request("GET", "/api/groups/invitations/pending", bob, null));

        api.request("POST", "/api/groups/invitations/" + pending.get(0).get("id").asString() + "/decline", bob, null)
                .andExpect(status().isNoContent());

        api.request("GET", "/api/groups/" + groupId, bob, null).andExpect(status().isNotFound());
        assertThat(api.ids(api.json(api.request("GET", "/api/chats", bob, null)), "id")).doesNotContain(groupId);

        // A past decline never blocks a fresh invitation.
        api.request("POST", "/api/groups/" + groupId + "/invitations", alice, Map.of("userIds", List.of(bob.id().toString())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.pendingInvitees", hasSize(1)));
    }

    @Test
    void onlyTheInviteeCanRespondAndOnlyOnce() throws Exception {
        TestUser alice = api.user(uniq("ga"));
        TestUser bob = api.user(uniq("gb"));
        TestUser carol = api.user(uniq("gc"));
        api.becomeContacts(alice, bob);
        api.request("POST", "/api/groups", alice, Map.of("name", "Private", "memberIds", List.of(bob.id().toString())))
                .andExpect(status().isCreated());
        String invitationId = api.json(api.request("GET", "/api/groups/invitations/pending", bob, null))
                .get(0).get("id").asString();

        api.request("POST", "/api/groups/invitations/" + invitationId + "/accept", carol, null)
                .andExpect(status().isForbidden());
        api.request("POST", "/api/groups/invitations/" + invitationId + "/accept", alice, null)
                .andExpect(status().isForbidden());

        api.request("POST", "/api/groups/invitations/" + invitationId + "/accept", bob, null).andExpect(status().isOk());
        api.request("POST", "/api/groups/invitations/" + invitationId + "/accept", bob, null)
                .andExpect(status().isConflict());
    }

    @Test
    void aMemberCanInviteMoreOfTheirContactsAndDuplicatesAreSkipped() throws Exception {
        TestUser alice = api.user(uniq("ga"));
        TestUser bob = api.user(uniq("gb"));
        TestUser carol = api.user(uniq("gc"));
        UUID groupId = api.groupOf("Growing", alice, bob);
        api.becomeContacts(bob, carol);

        api.request("POST", "/api/groups/" + groupId + "/invitations", bob, Map.of("userIds", List.of(carol.id().toString())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.pendingInvitees", hasSize(1)));
        // Inviting again (already pending) or inviting someone already in the group changes nothing.
        api.request("POST", "/api/groups/" + groupId + "/invitations", bob,
                        Map.of("userIds", List.of(carol.id().toString(), alice.id().toString())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.pendingInvitees", hasSize(1)));
    }

    @Test
    void aNonMemberCannotInviteOrViewAGroup() throws Exception {
        TestUser alice = api.user(uniq("ga"));
        TestUser bob = api.user(uniq("gb"));
        TestUser outsider = api.user(uniq("go"));
        api.becomeContacts(outsider, alice);
        UUID groupId = api.groupOf("Members only", alice, bob);

        api.request("GET", "/api/groups/" + groupId, outsider, null).andExpect(status().isNotFound());
        api.request("POST", "/api/groups/" + groupId + "/invitations", outsider,
                        Map.of("userIds", List.of(alice.id().toString())))
                .andExpect(status().isNotFound());
    }

    // ---- messaging in a group ----

    @Test
    void everyMemberCanSendAndReceiveGroupMessages() throws Exception {
        TestUser alice = api.user(uniq("ga"));
        TestUser bob = api.user(uniq("gb"));
        TestUser carol = api.user(uniq("gc"));
        UUID groupId = api.groupOf("Chatty", alice, bob, carol);

        api.sendMessage(alice, groupId, "hello everyone");
        api.sendMessage(carol, groupId, "hi alice");

        for (TestUser member : List.of(alice, bob, carol)) {
            JsonNode page = api.json(api.request("GET", "/api/chats/" + groupId + "/messages", member, null)
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.messages", hasSize(2))));
            assertThat(page.get("messages").get(0).get("content").asString()).isEqualTo("hello everyone");
            assertThat(page.get("messages").get(1).get("sender").get("username").asString()).isEqualTo(carol.username());
        }
    }

    @Test
    void aNonMemberAndAStillPendingInviteeCannotReadOrPostToAGroup() throws Exception {
        TestUser alice = api.user(uniq("ga"));
        TestUser bob = api.user(uniq("gb"));
        TestUser pendingUser = api.user(uniq("gp"));
        TestUser outsider = api.user(uniq("go"));
        UUID groupId = api.groupOf("Closed", alice, bob);
        api.becomeContacts(alice, pendingUser);
        api.request("POST", "/api/groups/" + groupId + "/invitations", alice,
                        Map.of("userIds", List.of(pendingUser.id().toString())))
                .andExpect(status().isOk());
        api.sendMessage(alice, groupId, "secret plans");

        for (TestUser nonMember : List.of(pendingUser, outsider)) {
            api.request("GET", "/api/chats/" + groupId + "/messages", nonMember, null).andExpect(status().isNotFound());
            api.request("POST", "/api/chats/" + groupId + "/messages", nonMember, Map.of("content", "let me in"))
                    .andExpect(status().isNotFound());
        }
    }

    @Test
    void theChatListIsSortedByTheLatestMessageAcrossDirectChatsAndGroups() throws Exception {
        TestUser alice = api.user(uniq("ga"));
        TestUser bob = api.user(uniq("gb"));
        TestUser carol = api.user(uniq("gc"));
        UUID direct = api.becomeContacts(alice, bob);
        UUID group = api.groupOf("Sorted", alice, carol);

        api.sendMessage(alice, direct, "older, in the direct chat");
        Thread.sleep(15);
        api.sendMessage(carol, group, "newer, in the group");

        JsonNode chats = api.json(api.request("GET", "/api/chats", alice, null));
        assertThat(chats.get(0).get("id").asString()).isEqualTo(group.toString());
        assertThat(chats.get(0).get("lastMessage").get("senderUsername").asString()).isEqualTo(carol.username());

        Thread.sleep(15);
        api.sendMessage(bob, direct, "now the direct chat is newest");
        chats = api.json(api.request("GET", "/api/chats", alice, null));
        assertThat(chats.get(0).get("id").asString()).isEqualTo(direct.toString());
    }

    // ---- delivered / read in a group ----

    @Test
    void aGroupMessageIsDeliveredOnlyOnceEveryMemberHasItAndReadOnlyOnceEveryMemberReadIt() throws Exception {
        TestUser alice = api.user(uniq("ga"));
        TestUser bob = api.user(uniq("gb"));
        TestUser carol = api.user(uniq("gc"));
        UUID groupId = api.groupOf("Receipts", alice, bob, carol);
        String messageId = api.sendMessage(alice, groupId, "did everyone get this?").get("id").asString();
        String deliveredPath = "/api/chats/" + groupId + "/messages/" + messageId + "/delivered";

        assertThat(statusOf(alice, groupId, messageId)).isEqualTo("SENT");

        api.request("POST", deliveredPath, bob, null).andExpect(status().isOk());
        assertThat(statusOf(alice, groupId, messageId)).as("only Bob has it so far").isEqualTo("SENT");

        api.request("POST", deliveredPath, carol, null).andExpect(status().isOk());
        assertThat(statusOf(alice, groupId, messageId)).as("now everyone has it").isEqualTo("DELIVERED");

        api.request("POST", "/api/chats/" + groupId + "/messages/read", bob, null).andExpect(status().isNoContent());
        assertThat(statusOf(alice, groupId, messageId)).as("Carol hasn't read it yet").isEqualTo("DELIVERED");

        api.request("POST", "/api/chats/" + groupId + "/messages/read", carol, null).andExpect(status().isNoContent());
        assertThat(statusOf(alice, groupId, messageId)).as("everyone has read it").isEqualTo("READ");
    }

    @Test
    void unreadCountsAreTrackedPerMemberInAGroup() throws Exception {
        TestUser alice = api.user(uniq("ga"));
        TestUser bob = api.user(uniq("gb"));
        TestUser carol = api.user(uniq("gc"));
        UUID groupId = api.groupOf("Unread", alice, bob, carol);
        api.sendMessage(alice, groupId, "one");
        api.sendMessage(alice, groupId, "two");

        assertThat(unreadOf(bob, groupId)).isEqualTo(2);
        assertThat(unreadOf(carol, groupId)).isEqualTo(2);
        assertThat(unreadOf(alice, groupId)).as("your own messages are never unread").isEqualTo(0);

        api.request("POST", "/api/chats/" + groupId + "/messages/read", bob, null).andExpect(status().isNoContent());
        assertThat(unreadOf(bob, groupId)).isEqualTo(0);
        assertThat(unreadOf(carol, groupId)).as("Carol's own count is unaffected by Bob reading").isEqualTo(2);
    }

    @Test
    void someoneWhoJoinsLaterDoesNotHoldBackOldMessagesFromBeingReadNorSeeThemAsUnread() throws Exception {
        TestUser alice = api.user(uniq("ga"));
        TestUser bob = api.user(uniq("gb"));
        TestUser latecomer = api.user(uniq("gl"));
        UUID groupId = api.groupOf("Late", alice, bob);
        String messageId = api.sendMessage(alice, groupId, "before the latecomer joined").get("id").asString();

        api.becomeContacts(alice, latecomer);
        api.request("POST", "/api/groups/" + groupId + "/invitations", alice, Map.of("userIds", List.of(latecomer.id().toString())))
                .andExpect(status().isOk());
        api.acceptGroupInvitation(latecomer, groupId.toString());

        api.request("POST", "/api/chats/" + groupId + "/messages/" + messageId + "/delivered", bob, null);
        api.request("POST", "/api/chats/" + groupId + "/messages/read", bob, null).andExpect(status().isNoContent());

        assertThat(statusOf(alice, groupId, messageId))
                .as("the latecomer never received this message, so cannot stop it counting as read")
                .isEqualTo("READ");
        assertThat(unreadOf(latecomer, groupId)).isEqualTo(0);
    }

    // ---- encryption ----

    @Test
    void theGroupNameIsEncryptedAtRestButReadableThroughTheApi() throws Exception {
        TestUser alice = api.user(uniq("ga"));
        TestUser bob = api.user(uniq("gb"));
        api.becomeContacts(alice, bob);
        String secretName = "Surprise party for " + uniq("zz");

        JsonNode group = api.json(api.request("POST", "/api/groups", alice,
                        Map.of("name", secretName, "memberIds", List.of(bob.id().toString())))
                .andExpect(status().isCreated()));

        String stored = jdbcTemplate.queryForObject(
                "SELECT name FROM conversations WHERE id = ?::uuid", String.class, group.get("id").asString());
        assertThat(stored).isNotNull().doesNotContain(secretName).doesNotContain("Surprise");
        api.request("GET", "/api/groups/" + group.get("id").asString(), alice, null)
                .andExpect(jsonPath("$.name").value(secretName));
    }

    // ---- helpers ----

    private String statusOf(TestUser viewer, UUID chatId, String messageId) throws Exception {
        JsonNode page = api.json(api.request("GET", "/api/chats/" + chatId + "/messages", viewer, null));
        for (JsonNode message : page.get("messages")) {
            if (message.get("id").asString().equals(messageId)) {
                return message.get("status").asString();
            }
        }
        throw new IllegalStateException("message not found");
    }

    private int unreadOf(TestUser viewer, UUID chatId) throws Exception {
        for (JsonNode chat : api.json(api.request("GET", "/api/chats", viewer, null))) {
            if (chat.get("id").asString().equals(chatId.toString())) {
                return chat.get("unreadCount").asInt();
            }
        }
        throw new IllegalStateException("chat not in list");
    }
}
