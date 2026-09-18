package com.mobilemessenger.backend.contact;

import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.notNullValue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.transaction.annotation.Transactional;
import com.mobilemessenger.backend.user.UserRepository;
import tools.jackson.databind.json.JsonMapper;

/**
 * End-to-end tests for the contact invitation lifecycle (send, list pending,
 * accept, decline) and the resulting contact relationship, against a real
 * database. Each test runs in its own transaction that is rolled back
 * afterwards.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class ContactInvitationControllerIntegrationTest {

    private static final String STRONG_PASSWORD = "Str0ng!Pass";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    private final JsonMapper jsonMapper = JsonMapper.builder().build();

    @Test
    void sendInvitationRequiresAuthentication() throws Exception {
        mockMvc.perform(sendInvitationRequest(null, UUID.randomUUID()))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void sendInvitationSucceeds() throws Exception {
        RegisteredUser alice = register("alice_send", "alice.send@example.com");
        RegisteredUser bob = register("bob_send", "bob.send@example.com");

        mockMvc.perform(sendInvitationRequest(alice.token, bob.id))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id", notNullValue()))
                .andExpect(jsonPath("$.status").value("PENDING"))
                .andExpect(jsonPath("$.sender.username").value("alice_send"))
                .andExpect(jsonPath("$.recipient.username").value("bob_send"))
                .andExpect(jsonPath("$.createdAt", notNullValue()));
    }

    @Test
    void sentInvitationAppearsInRecipientPendingList() throws Exception {
        RegisteredUser alice = register("alice_pending", "alice.pending@example.com");
        RegisteredUser bob = register("bob_pending", "bob.pending@example.com");

        mockMvc.perform(sendInvitationRequest(alice.token, bob.id)).andExpect(status().isCreated());

        mockMvc.perform(get("/api/contacts/invitations/pending").header("Authorization", "Bearer " + bob.token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].sender.username").value("alice_pending"));
    }

    @Test
    void pendingListRequiresAuthentication() throws Exception {
        mockMvc.perform(get("/api/contacts/invitations/pending")).andExpect(status().isUnauthorized());
    }

    @Test
    void duplicatePendingInvitationIsRejected() throws Exception {
        RegisteredUser alice = register("alice_dup", "alice.dup@example.com");
        RegisteredUser bob = register("bob_dup", "bob.dup@example.com");

        mockMvc.perform(sendInvitationRequest(alice.token, bob.id)).andExpect(status().isCreated());

        mockMvc.perform(sendInvitationRequest(alice.token, bob.id))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error").value("An invitation is already pending"));
    }

    @Test
    void selfInvitationIsRejected() throws Exception {
        RegisteredUser alice = register("alice_self", "alice.self@example.com");

        mockMvc.perform(sendInvitationRequest(alice.token, alice.id))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("You cannot invite yourself"));
    }

    @Test
    void invitationToExistingContactIsRejected() throws Exception {
        RegisteredUser alice = register("alice_existing", "alice.existing@example.com");
        RegisteredUser bob = register("bob_existing", "bob.existing@example.com");
        UUID invitationId = sendInvitationAndGetId(alice.token, bob.id);
        acceptInvitation(bob.token, invitationId).andExpect(status().isOk());

        mockMvc.perform(sendInvitationRequest(alice.token, bob.id))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error").value("You are already contacts"));
    }

    @Test
    void reverseDirectionInvitationAutoAcceptsInstead() throws Exception {
        RegisteredUser alice = register("alice_reverse", "alice.reverse@example.com");
        RegisteredUser bob = register("bob_reverse", "bob.reverse@example.com");
        UUID forwardId = sendInvitationAndGetId(alice.token, bob.id);

        mockMvc.perform(sendInvitationRequest(bob.token, alice.id))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value(forwardId.toString()))
                .andExpect(jsonPath("$.status").value("ACCEPTED"));

        mockMvc.perform(get("/api/contacts").header("Authorization", "Bearer " + bob.token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].user.username").value("alice_reverse"));
    }

    @Test
    void recipientCanAcceptInvitation() throws Exception {
        RegisteredUser alice = register("alice_accept", "alice.accept@example.com");
        RegisteredUser bob = register("bob_accept", "bob.accept@example.com");
        UUID invitationId = sendInvitationAndGetId(alice.token, bob.id);

        acceptInvitation(bob.token, invitationId)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("ACCEPTED"))
                .andExpect(jsonPath("$.respondedAt", notNullValue()));
    }

    @Test
    void acceptingInvitationCreatesMutualContactRelationship() throws Exception {
        RegisteredUser alice = register("alice_mutual", "alice.mutual@example.com");
        RegisteredUser bob = register("bob_mutual", "bob.mutual@example.com");
        UUID invitationId = sendInvitationAndGetId(alice.token, bob.id);

        acceptInvitation(bob.token, invitationId).andExpect(status().isOk());

        mockMvc.perform(get("/api/contacts").header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].user.username").value("bob_mutual"));

        mockMvc.perform(get("/api/contacts").header("Authorization", "Bearer " + bob.token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].user.username").value("alice_mutual"));
    }

    @Test
    void senderCannotAcceptOwnSentInvitation() throws Exception {
        RegisteredUser alice = register("alice_noaccept", "alice.noaccept@example.com");
        RegisteredUser bob = register("bob_noaccept", "bob.noaccept@example.com");
        UUID invitationId = sendInvitationAndGetId(alice.token, bob.id);

        acceptInvitation(alice.token, invitationId)
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error").value("You are not authorized to respond to this invitation"));
    }

    @Test
    void unrelatedUserCannotAcceptInvitation() throws Exception {
        RegisteredUser alice = register("alice_unrelated", "alice.unrelated@example.com");
        RegisteredUser bob = register("bob_unrelated", "bob.unrelated@example.com");
        RegisteredUser carol = register("carol_unrelated", "carol.unrelated@example.com");
        UUID invitationId = sendInvitationAndGetId(alice.token, bob.id);

        acceptInvitation(carol.token, invitationId)
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error").value("You are not authorized to respond to this invitation"));
    }

    @Test
    void alreadyAcceptedInvitationCannotBeAcceptedAgain() throws Exception {
        RegisteredUser alice = register("alice_reaccept", "alice.reaccept@example.com");
        RegisteredUser bob = register("bob_reaccept", "bob.reaccept@example.com");
        UUID invitationId = sendInvitationAndGetId(alice.token, bob.id);
        acceptInvitation(bob.token, invitationId).andExpect(status().isOk());

        acceptInvitation(bob.token, invitationId)
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error").value("This invitation has already been responded to"));
    }

    @Test
    void recipientCanDeclineInvitation() throws Exception {
        RegisteredUser alice = register("alice_decline", "alice.decline@example.com");
        RegisteredUser bob = register("bob_decline", "bob.decline@example.com");
        UUID invitationId = sendInvitationAndGetId(alice.token, bob.id);

        declineInvitation(bob.token, invitationId)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("DECLINED"))
                .andExpect(jsonPath("$.respondedAt", notNullValue()));
    }

    @Test
    void decliningInvitationDoesNotCreateContactRelationship() throws Exception {
        RegisteredUser alice = register("alice_nocontact", "alice.nocontact@example.com");
        RegisteredUser bob = register("bob_nocontact", "bob.nocontact@example.com");
        UUID invitationId = sendInvitationAndGetId(alice.token, bob.id);

        declineInvitation(bob.token, invitationId).andExpect(status().isOk());

        mockMvc.perform(get("/api/contacts").header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(0)));
    }

    @Test
    void senderCannotDeclineOwnSentInvitation() throws Exception {
        RegisteredUser alice = register("alice_nodecline", "alice.nodecline@example.com");
        RegisteredUser bob = register("bob_nodecline", "bob.nodecline@example.com");
        UUID invitationId = sendInvitationAndGetId(alice.token, bob.id);

        declineInvitation(alice.token, invitationId)
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error").value("You are not authorized to respond to this invitation"));
    }

    @Test
    void unrelatedUserCannotDeclineInvitation() throws Exception {
        RegisteredUser alice = register("alice_unrel_dec", "alice.unrel.dec@example.com");
        RegisteredUser bob = register("bob_unrel_dec", "bob.unrel.dec@example.com");
        RegisteredUser carol = register("carol_unrel_dec", "carol.unrel.dec@example.com");
        UUID invitationId = sendInvitationAndGetId(alice.token, bob.id);

        declineInvitation(carol.token, invitationId)
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error").value("You are not authorized to respond to this invitation"));
    }

    @Test
    void alreadyDeclinedInvitationCannotBeDeclinedAgain() throws Exception {
        RegisteredUser alice = register("alice_redecline", "alice.redecline@example.com");
        RegisteredUser bob = register("bob_redecline", "bob.redecline@example.com");
        UUID invitationId = sendInvitationAndGetId(alice.token, bob.id);
        declineInvitation(bob.token, invitationId).andExpect(status().isOk());

        declineInvitation(bob.token, invitationId)
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error").value("This invitation has already been responded to"));
    }

    @Test
    void declinedInvitationAllowsSendingANewInvitation() throws Exception {
        RegisteredUser alice = register("alice_resend", "alice.resend@example.com");
        RegisteredUser bob = register("bob_resend", "bob.resend@example.com");
        UUID firstInvitationId = sendInvitationAndGetId(alice.token, bob.id);
        declineInvitation(bob.token, firstInvitationId).andExpect(status().isOk());

        mockMvc.perform(sendInvitationRequest(alice.token, bob.id))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.status").value("PENDING"));
    }

    @Test
    void pendingInvitationPersistsAcrossRequests() throws Exception {
        RegisteredUser alice = register("alice_persist", "alice.persist@example.com");
        RegisteredUser bob = register("bob_persist", "bob.persist@example.com");
        UUID invitationId = sendInvitationAndGetId(alice.token, bob.id);

        mockMvc.perform(get("/api/contacts/invitations/pending").header("Authorization", "Bearer " + bob.token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value(invitationId.toString()));
    }

    private UUID sendInvitationAndGetId(String senderToken, UUID recipientId) throws Exception {
        MvcResult result = mockMvc.perform(sendInvitationRequest(senderToken, recipientId))
                .andExpect(status().isCreated())
                .andReturn();
        return UUID.fromString(
                jsonMapper.readTree(result.getResponse().getContentAsString()).get("id").asString());
    }

    private org.springframework.test.web.servlet.ResultActions acceptInvitation(String token, UUID invitationId)
            throws Exception {
        return mockMvc.perform(post("/api/contacts/invitations/" + invitationId + "/accept")
                .header("Authorization", "Bearer " + token));
    }

    private org.springframework.test.web.servlet.ResultActions declineInvitation(String token, UUID invitationId)
            throws Exception {
        return mockMvc.perform(post("/api/contacts/invitations/" + invitationId + "/decline")
                .header("Authorization", "Bearer " + token));
    }

    private MockHttpServletRequestBuilder sendInvitationRequest(String token, UUID recipientId) throws Exception {
        String body = jsonMapper.writeValueAsString(new SendInvitationPayload(recipientId));
        MockHttpServletRequestBuilder request =
                post("/api/contacts/invitations").contentType(MediaType.APPLICATION_JSON).content(body);
        return token == null ? request : request.header("Authorization", "Bearer " + token);
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
}
