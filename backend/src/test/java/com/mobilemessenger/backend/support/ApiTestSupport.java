package com.mobilemessenger.backend.support;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.mobilemessenger.backend.user.UserRepository;
import java.util.List;
import java.util.UUID;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.ResultActions;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

/**
 * Boilerplate shared by the integration tests of the group/search/poll
 * features: creating verified users, making them contacts, and sending
 * authenticated JSON requests - all through the real HTTP API, exactly as a
 * client would.
 */
public class ApiTestSupport {

    public static final String PASSWORD = "Str0ng!Pass";

    public record TestUser(UUID id, String username, String token) {}

    private final MockMvc mockMvc;
    private final UserRepository userRepository;
    private final JsonMapper jsonMapper = JsonMapper.builder().build();

    public ApiTestSupport(MockMvc mockMvc, UserRepository userRepository) {
        this.mockMvc = mockMvc;
        this.userRepository = userRepository;
    }

    /** Registers a user through the API and marks their email verified, so the whole API is reachable. */
    public TestUser user(String username) throws Exception {
        String body = jsonMapper.writeValueAsString(
                new java.util.LinkedHashMap<>(java.util.Map.of(
                        "username", username, "email", username + "@example.com", "password", PASSWORD)));
        MvcResult result = mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isCreated())
                .andReturn();
        JsonNode node = jsonMapper.readTree(result.getResponse().getContentAsString());
        UUID id = UUID.fromString(node.get("user").get("id").asString());
        userRepository.findById(id).ifPresent(user -> {
            user.setEmailVerified(true);
            userRepository.save(user);
        });
        return new TestUser(id, username, node.get("token").asString());
    }

    /** Sends a contact invitation and accepts it, returning the id of their direct chat. */
    public UUID becomeContacts(TestUser a, TestUser b) throws Exception {
        JsonNode invitation = json(request("POST", "/api/contacts/invitations", a, java.util.Map.of("recipientId", b.id().toString()))
                .andExpect(status().isCreated()));
        request("POST", "/api/contacts/invitations/" + invitation.get("id").asString() + "/accept", b, null)
                .andExpect(status().isOk());
        for (JsonNode chat : json(request("GET", "/api/chats", a, null).andExpect(status().isOk()))) {
            if (chat.hasNonNull("otherUser") && chat.get("otherUser").get("id").asString().equals(b.id().toString())) {
                return UUID.fromString(chat.get("id").asString());
            }
        }
        throw new IllegalStateException("no direct chat created");
    }

    /** Creates a group and has every invitee accept, returning the group's id. */
    public UUID groupOf(String name, TestUser creator, TestUser... others) throws Exception {
        for (TestUser other : others) {
            becomeContacts(creator, other);
        }
        JsonNode group = json(request("POST", "/api/groups", creator, java.util.Map.of(
                        "name", name, "memberIds", java.util.Arrays.stream(others).map(u -> u.id().toString()).toList()))
                .andExpect(status().isCreated()));
        for (TestUser other : others) {
            acceptGroupInvitation(other, group.get("id").asString());
        }
        return UUID.fromString(group.get("id").asString());
    }

    public void acceptGroupInvitation(TestUser invitee, String groupId) throws Exception {
        for (JsonNode invitation : json(request("GET", "/api/groups/invitations/pending", invitee, null).andExpect(status().isOk()))) {
            if (invitation.get("groupId").asString().equals(groupId)) {
                request("POST", "/api/groups/invitations/" + invitation.get("id").asString() + "/accept", invitee, null)
                        .andExpect(status().isOk());
                return;
            }
        }
        throw new IllegalStateException("no pending invitation to " + groupId);
    }

    public JsonNode sendMessage(TestUser sender, UUID chatId, String content) throws Exception {
        return json(request("POST", "/api/chats/" + chatId + "/messages", sender, java.util.Map.of("content", content))
                .andExpect(status().isCreated()));
    }

    public ResultActions request(String method, String path, TestUser user, Object body) throws Exception {
        var builder = switch (method) {
            case "GET" -> get(path);
            case "POST" -> post(path);
            case "PUT" -> org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put(path);
            case "DELETE" -> org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete(path);
            default -> throw new IllegalArgumentException(method);
        };
        if (user != null) {
            builder.header("Authorization", "Bearer " + user.token());
        }
        if (body != null) {
            builder.contentType(MediaType.APPLICATION_JSON).content(jsonMapper.writeValueAsString(body));
        }
        return mockMvc.perform(builder);
    }

    public JsonNode json(ResultActions actions) throws Exception {
        return jsonMapper.readTree(actions.andReturn().getResponse().getContentAsString());
    }

    public List<String> ids(JsonNode array, String field) {
        java.util.ArrayList<String> out = new java.util.ArrayList<>();
        array.forEach(n -> out.add(n.get(field).asString()));
        return out;
    }
}
