package com.mobilemessenger.backend.chat.poll;

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
 * Polls in group chats: creation and validation, public vs anonymous
 * visibility, voting / changing / retracting a vote, persistence, and
 * encryption of the option text at rest.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class PollControllerIntegrationTest {

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

    private JsonNode createPoll(TestUser creator, UUID chat, boolean anonymous, String... options) throws Exception {
        return api.json(api.request("POST", "/api/chats/" + chat + "/polls", creator,
                        Map.of("question", "Where should we eat?", "options", List.of(options), "anonymous", anonymous))
                .andExpect(status().isCreated()));
    }

    private JsonNode poll(TestUser viewer, UUID chat, String pollId) throws Exception {
        return api.json(api.request("GET", "/api/chats/" + chat + "/polls/" + pollId, viewer, null)
                .andExpect(status().isOk()));
    }

    private JsonNode vote(TestUser voter, UUID chat, String pollId, String optionId) throws Exception {
        return api.json(api.request("PUT", "/api/chats/" + chat + "/polls/" + pollId + "/vote", voter,
                        Map.of("optionId", optionId))
                .andExpect(status().isOk()));
    }

    private static JsonNode option(JsonNode poll, int index) {
        return poll.get("options").get(index);
    }

    // ---- creating ----

    @Test
    void aGroupMemberCanCreateAPollAndItShowsUpAsAMessageForEveryone() throws Exception {
        TestUser alice = api.user(uniq("pa"));
        TestUser bob = api.user(uniq("pb"));
        UUID group = api.groupOf("Poll group", alice, bob);

        JsonNode message = createPoll(alice, group, false, "Pizza", "Sushi", "Tacos");

        assertThat(message.get("content").asString()).isEqualTo("Where should we eat?");
        assertThat(message.get("poll").get("options")).hasSize(3);
        assertThat(message.get("poll").get("anonymous").asBoolean()).isFalse();
        assertThat(message.get("poll").get("totalVotes").asInt()).isZero();

        // It is an ordinary timeline message for the other member...
        api.request("GET", "/api/chats/" + group + "/messages", bob, null)
                .andExpect(jsonPath("$.messages", hasSize(1)))
                .andExpect(jsonPath("$.messages[0].poll.question").value("Where should we eat?"));
        // ...and it is what the chat list previews and sorts by.
        JsonNode chats = api.json(api.request("GET", "/api/chats", bob, null));
        assertThat(chats.get(0).get("lastMessage").get("content").asString()).isEqualTo("Where should we eat?");
    }

    @Test
    void pollsAreOnlyAllowedInGroupChats() throws Exception {
        TestUser alice = api.user(uniq("pa"));
        TestUser bob = api.user(uniq("pb"));
        UUID direct = api.becomeContacts(alice, bob);

        api.request("POST", "/api/chats/" + direct + "/polls", alice,
                        Map.of("question", "Q?", "options", List.of("a", "b"), "anonymous", false))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Polls can only be created in group chats"));
    }

    @Test
    void pollInputIsValidated() throws Exception {
        TestUser alice = api.user(uniq("pa"));
        TestUser bob = api.user(uniq("pb"));
        UUID group = api.groupOf("Validation", alice, bob);
        String path = "/api/chats/" + group + "/polls";

        api.request("POST", path, alice, Map.of("question", " ", "options", List.of("a", "b"), "anonymous", false))
                .andExpect(status().isBadRequest());
        api.request("POST", path, alice, Map.of("question", "Q?", "options", List.of("only one"), "anonymous", false))
                .andExpect(status().isBadRequest());
        api.request("POST", path, alice,
                        Map.of("question", "Q?", "options", List.of("a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k"),
                                "anonymous", false))
                .andExpect(status().isBadRequest());
        api.request("POST", path, alice, Map.of("question", "Q?", "options", List.of("a", " "), "anonymous", false))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Poll options can't be empty"));
        api.request("POST", path, alice, Map.of("question", "Q?", "options", List.of("Same", "same"), "anonymous", false))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Poll options must all be different"));

        api.request("GET", "/api/chats/" + group + "/messages", alice, null).andExpect(jsonPath("$.messages", hasSize(0)));
    }

    @Test
    void aNonMemberCannotCreateViewOrVoteInAPoll() throws Exception {
        TestUser alice = api.user(uniq("pa"));
        TestUser bob = api.user(uniq("pb"));
        TestUser outsider = api.user(uniq("po"));
        UUID group = api.groupOf("Private poll", alice, bob);
        JsonNode message = createPoll(alice, group, false, "Yes", "No");
        String pollId = message.get("poll").get("id").asString();
        String optionId = option(message.get("poll"), 0).get("id").asString();

        api.request("POST", "/api/chats/" + group + "/polls", outsider,
                        Map.of("question", "Q?", "options", List.of("a", "b"), "anonymous", false))
                .andExpect(status().isNotFound());
        api.request("GET", "/api/chats/" + group + "/polls/" + pollId, outsider, null).andExpect(status().isNotFound());
        api.request("PUT", "/api/chats/" + group + "/polls/" + pollId + "/vote", outsider, Map.of("optionId", optionId))
                .andExpect(status().isNotFound());
    }

    // ---- voting ----

    @Test
    void votingCountsTheVoteAndRemembersItPerViewer() throws Exception {
        TestUser alice = api.user(uniq("pa"));
        TestUser bob = api.user(uniq("pb"));
        UUID group = api.groupOf("Voting", alice, bob);
        JsonNode created = createPoll(alice, group, false, "Pizza", "Sushi");
        String pollId = created.get("poll").get("id").asString();
        String pizza = option(created.get("poll"), 0).get("id").asString();

        JsonNode afterVote = vote(bob, group, pollId, pizza);

        assertThat(option(afterVote, 0).get("voteCount").asInt()).isEqualTo(1);
        assertThat(afterVote.get("totalVotes").asInt()).isEqualTo(1);
        assertThat(afterVote.get("myOptionId").asString()).isEqualTo(pizza);
        // Alice sees the same tally but her own choice is still "none".
        JsonNode aliceView = poll(alice, group, pollId);
        assertThat(aliceView.get("totalVotes").asInt()).isEqualTo(1);
        assertThat(aliceView.get("myOptionId").isNull()).isTrue();
    }

    @Test
    void aVoteCanBeChangedButCountsOnlyOnce() throws Exception {
        TestUser alice = api.user(uniq("pa"));
        TestUser bob = api.user(uniq("pb"));
        UUID group = api.groupOf("Changing", alice, bob);
        JsonNode created = createPoll(alice, group, false, "Pizza", "Sushi");
        String pollId = created.get("poll").get("id").asString();
        String pizza = option(created.get("poll"), 0).get("id").asString();
        String sushi = option(created.get("poll"), 1).get("id").asString();

        vote(bob, group, pollId, pizza);
        JsonNode changed = vote(bob, group, pollId, sushi);

        assertThat(option(changed, 0).get("voteCount").asInt()).isZero();
        assertThat(option(changed, 1).get("voteCount").asInt()).isEqualTo(1);
        assertThat(changed.get("totalVotes").asInt()).as("one person, one vote").isEqualTo(1);
        assertThat(changed.get("myOptionId").asString()).isEqualTo(sushi);
    }

    @Test
    void aVoteCanBeRetractedAndCastAgain() throws Exception {
        TestUser alice = api.user(uniq("pa"));
        TestUser bob = api.user(uniq("pb"));
        UUID group = api.groupOf("Retracting", alice, bob);
        JsonNode created = createPoll(alice, group, false, "Pizza", "Sushi");
        String pollId = created.get("poll").get("id").asString();
        String pizza = option(created.get("poll"), 0).get("id").asString();
        vote(bob, group, pollId, pizza);

        JsonNode retracted = api.json(api.request("DELETE", "/api/chats/" + group + "/polls/" + pollId + "/vote", bob, null)
                .andExpect(status().isOk()));

        assertThat(retracted.get("totalVotes").asInt()).isZero();
        assertThat(retracted.get("myOptionId").isNull()).isTrue();
        // Retracting when there is nothing to retract is harmless.
        api.request("DELETE", "/api/chats/" + group + "/polls/" + pollId + "/vote", bob, null).andExpect(status().isOk());
        assertThat(vote(bob, group, pollId, pizza).get("totalVotes").asInt()).isEqualTo(1);
    }

    @Test
    void anOptionFromAnotherPollCannotBeVotedFor() throws Exception {
        TestUser alice = api.user(uniq("pa"));
        TestUser bob = api.user(uniq("pb"));
        UUID group = api.groupOf("Mixing", alice, bob);
        JsonNode first = createPoll(alice, group, false, "A", "B");
        JsonNode second = createPoll(alice, group, false, "C", "D");

        api.request("PUT", "/api/chats/" + group + "/polls/" + first.get("poll").get("id").asString() + "/vote", bob,
                        Map.of("optionId", option(second.get("poll"), 0).get("id").asString()))
                .andExpect(status().isBadRequest());
    }

    // ---- public vs anonymous ----

    @Test
    void aPublicPollShowsWhoVotedForWhat() throws Exception {
        TestUser alice = api.user(uniq("pa"));
        TestUser bob = api.user(uniq("pb"));
        TestUser carol = api.user(uniq("pc"));
        UUID group = api.groupOf("Public", alice, bob, carol);
        JsonNode created = createPoll(alice, group, false, "Pizza", "Sushi");
        String pollId = created.get("poll").get("id").asString();
        vote(bob, group, pollId, option(created.get("poll"), 0).get("id").asString());
        vote(carol, group, pollId, option(created.get("poll"), 0).get("id").asString());

        JsonNode seenByAlice = poll(alice, group, pollId);

        assertThat(option(seenByAlice, 0).get("voters")).hasSize(2);
        assertThat(api.ids(option(seenByAlice, 0).get("voters"), "username"))
                .containsExactlyInAnyOrder(bob.username(), carol.username());
        assertThat(option(seenByAlice, 1).get("voters")).isEmpty();
    }

    @Test
    void anAnonymousPollShowsTotalsButNeverWhoVotedForWhat() throws Exception {
        TestUser alice = api.user(uniq("pa"));
        TestUser bob = api.user(uniq("pb"));
        TestUser carol = api.user(uniq("pc"));
        UUID group = api.groupOf("Anonymous", alice, bob, carol);
        JsonNode created = createPoll(alice, group, true, "Pizza", "Sushi");
        String pollId = created.get("poll").get("id").asString();
        String pizza = option(created.get("poll"), 0).get("id").asString();
        vote(bob, group, pollId, pizza);
        JsonNode carolsVote = vote(carol, group, pollId, pizza);

        // Not even the creator (or the voter, for others' votes) can see voters.
        for (TestUser viewer : List.of(alice, bob, carol)) {
            JsonNode view = poll(viewer, group, pollId);
            assertThat(view.get("anonymous").asBoolean()).isTrue();
            assertThat(option(view, 0).get("voteCount").asInt()).isEqualTo(2);
            assertThat(option(view, 0).get("voters").isNull()).as("voters is null, not an empty list").isTrue();
            assertThat(option(view, 1).get("voters").isNull()).isTrue();
        }
        assertThat(carolsVote.get("myOptionId").asString()).isEqualTo(pizza);
        assertThat(poll(alice, group, pollId).get("myOptionId").isNull()).isTrue();

        // The message listing (what a client loads on start) leaks nothing either.
        JsonNode messages = api.json(api.request("GET", "/api/chats/" + group + "/messages", alice, null));
        assertThat(messages.get("messages").get(0).get("poll").get("options").get(0).get("voters").isNull()).isTrue();
    }

    @Test
    void anAnonymousVoteCanStillBeChangedAndRetractedByItsVoter() throws Exception {
        TestUser alice = api.user(uniq("pa"));
        TestUser bob = api.user(uniq("pb"));
        UUID group = api.groupOf("Anon change", alice, bob);
        JsonNode created = createPoll(alice, group, true, "Pizza", "Sushi");
        String pollId = created.get("poll").get("id").asString();
        String pizza = option(created.get("poll"), 0).get("id").asString();
        String sushi = option(created.get("poll"), 1).get("id").asString();

        vote(bob, group, pollId, pizza);
        JsonNode changed = vote(bob, group, pollId, sushi);
        assertThat(option(changed, 1).get("voteCount").asInt()).isEqualTo(1);

        JsonNode retracted = api.json(api.request("DELETE", "/api/chats/" + group + "/polls/" + pollId + "/vote", bob, null)
                .andExpect(status().isOk()));
        assertThat(retracted.get("totalVotes").asInt()).isZero();
    }

    // ---- persistence, deletion, editing, encryption ----

    @Test
    void voteStateIsPersistedAndComesBackWithTheMessageHistory() throws Exception {
        TestUser alice = api.user(uniq("pa"));
        TestUser bob = api.user(uniq("pb"));
        UUID group = api.groupOf("Persisted", alice, bob);
        JsonNode created = createPoll(alice, group, false, "Pizza", "Sushi");
        String pizza = option(created.get("poll"), 0).get("id").asString();
        vote(bob, group, created.get("poll").get("id").asString(), pizza);

        // A fresh load of history (as after an app restart) still has the poll, tally and own vote.
        JsonNode history = api.json(api.request("GET", "/api/chats/" + group + "/messages", bob, null));
        JsonNode reloaded = history.get("messages").get(0).get("poll");
        assertThat(reloaded.get("totalVotes").asInt()).isEqualTo(1);
        assertThat(reloaded.get("myOptionId").asString()).isEqualTo(pizza);
    }

    @Test
    void aDeletedPollCannotBeVotedInAndExposesNoPoll() throws Exception {
        TestUser alice = api.user(uniq("pa"));
        TestUser bob = api.user(uniq("pb"));
        UUID group = api.groupOf("Deleted", alice, bob);
        JsonNode created = createPoll(alice, group, false, "Pizza", "Sushi");
        String pollId = created.get("poll").get("id").asString();

        api.request("DELETE", "/api/chats/" + group + "/messages/" + created.get("id").asString(), alice, null)
                .andExpect(status().isNoContent());

        api.request("PUT", "/api/chats/" + group + "/polls/" + pollId + "/vote", bob,
                        Map.of("optionId", option(created.get("poll"), 0).get("id").asString()))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("This poll was deleted"));
        api.request("GET", "/api/chats/" + group + "/messages", bob, null)
                .andExpect(jsonPath("$.messages[0].deleted").value(true))
                .andExpect(jsonPath("$.messages[0].poll").doesNotExist());
    }

    @Test
    void aPollsQuestionCannotBeEdited() throws Exception {
        TestUser alice = api.user(uniq("pa"));
        TestUser bob = api.user(uniq("pb"));
        UUID group = api.groupOf("No edit", alice, bob);
        JsonNode created = createPoll(alice, group, false, "Pizza", "Sushi");

        api.request("PUT", "/api/chats/" + group + "/messages/" + created.get("id").asString(), alice,
                        Map.of("content", "changed question"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("A poll's question can't be edited"));
    }

    @Test
    void pollQuestionsAreSearchable() throws Exception {
        TestUser alice = api.user(uniq("pa"));
        TestUser bob = api.user(uniq("pb"));
        UUID group = api.groupOf("Searchable", alice, bob);
        createPoll(alice, group, false, "Pizza", "Sushi");

        api.request("GET", "/api/chats/" + group + "/messages/search?q=where should", bob, null)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.results", hasSize(1)))
                .andExpect(jsonPath("$.results[0].poll.options", hasSize(2)));
    }

    @Test
    void optionTextIsEncryptedAtRestButReadableThroughTheApi() throws Exception {
        TestUser alice = api.user(uniq("pa"));
        TestUser bob = api.user(uniq("pb"));
        UUID group = api.groupOf("Encrypted poll", alice, bob);
        String secretOption = "Quarterly layoffs " + uniq("zz");

        JsonNode created = createPoll(alice, group, false, secretOption, "Nothing");

        List<String> stored = jdbcTemplate.queryForList(
                "SELECT text FROM poll_options WHERE poll_id = ?::uuid", String.class, created.get("poll").get("id").asString());
        assertThat(stored).hasSize(2);
        assertThat(stored).noneMatch(text -> text.contains("layoffs") || text.contains("Nothing"));
        assertThat(option(created.get("poll"), 0).get("text").asString()).isEqualTo(secretOption);
    }
}
