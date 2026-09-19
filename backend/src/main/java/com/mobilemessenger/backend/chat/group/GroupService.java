package com.mobilemessenger.backend.chat.group;

import com.mobilemessenger.backend.chat.Conversation;
import com.mobilemessenger.backend.chat.ConversationParticipant;
import com.mobilemessenger.backend.chat.ConversationParticipantRepository;
import com.mobilemessenger.backend.chat.ConversationRepository;
import com.mobilemessenger.backend.chat.ParticipantRole;
import com.mobilemessenger.backend.chat.group.dto.GroupDetailsResponse;
import com.mobilemessenger.backend.chat.group.dto.GroupMemberResponse;
import com.mobilemessenger.backend.chat.group.dto.PendingGroupInvitationResponse;
import com.mobilemessenger.backend.chat.websocket.AfterCommit;
import com.mobilemessenger.backend.chat.websocket.ChatEvent;
import com.mobilemessenger.backend.chat.websocket.InvitationResolvedPayload;
import com.mobilemessenger.backend.chat.websocket.MemberJoinedPayload;
import com.mobilemessenger.backend.contact.ContactService;
import com.mobilemessenger.backend.contact.dto.ContactUserSummary;
import com.mobilemessenger.backend.contact.exception.InvitationAlreadyProcessedException;
import com.mobilemessenger.backend.contact.exception.NotInvitationRecipientException;
import com.mobilemessenger.backend.user.User;
import com.mobilemessenger.backend.user.UserRepository;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Group chats: creating a group, inviting people, and answering invitations.
 *
 * <p>Membership is only ever created by the invitee accepting - the inviter
 * never adds anyone unilaterally - and only your own contacts can be invited,
 * mirroring how 1:1 chats only exist between accepted contacts.
 */
@Service
public class GroupService {

    private final ConversationRepository conversationRepository;
    private final ConversationParticipantRepository participantRepository;
    private final GroupInvitationRepository invitationRepository;
    private final UserRepository userRepository;
    private final ContactService contactService;
    private final SimpMessagingTemplate messagingTemplate;

    public GroupService(
            ConversationRepository conversationRepository,
            ConversationParticipantRepository participantRepository,
            GroupInvitationRepository invitationRepository,
            UserRepository userRepository,
            ContactService contactService,
            SimpMessagingTemplate messagingTemplate) {
        this.conversationRepository = conversationRepository;
        this.participantRepository = participantRepository;
        this.invitationRepository = invitationRepository;
        this.userRepository = userRepository;
        this.contactService = contactService;
        this.messagingTemplate = messagingTemplate;
    }

    @Transactional
    public GroupDetailsResponse createGroup(UUID creatorId, String rawName, List<UUID> memberIds) {
        String name = rawName == null ? "" : rawName.trim();
        if (name.isEmpty()) {
            throw new InvalidGroupOperationException("Group name is required");
        }
        Set<UUID> invitees = validatedInvitees(creatorId, memberIds);
        if (invitees.isEmpty()) {
            throw new InvalidGroupOperationException("Invite at least one contact");
        }

        Conversation group = conversationRepository.saveAndFlush(Conversation.newGroup(name, creatorId));
        participantRepository.saveAndFlush(new ConversationParticipant(group.getId(), creatorId, ParticipantRole.ADMIN));
        for (UUID inviteeId : invitees) {
            createInvitation(group, creatorId, inviteeId);
        }
        return details(group);
    }

    /** Invites more of the caller's contacts. People already in the group, or already invited, are skipped. */
    @Transactional
    public GroupDetailsResponse invite(UUID groupId, UUID inviterId, List<UUID> userIds) {
        Conversation group = requireGroupMember(groupId, inviterId);
        for (UUID inviteeId : validatedInvitees(inviterId, userIds)) {
            boolean alreadyMember = participantRepository.findByConversationIdAndUserId(groupId, inviteeId).isPresent();
            boolean alreadyInvited = invitationRepository
                    .findByConversationIdAndInviteeIdAndStatus(groupId, inviteeId, GroupInvitationStatus.PENDING)
                    .isPresent();
            if (!alreadyMember && !alreadyInvited) {
                createInvitation(group, inviterId, inviteeId);
            }
        }
        return details(group);
    }

    public GroupDetailsResponse getGroup(UUID groupId, UUID userId) {
        return details(requireGroupMember(groupId, userId));
    }

    public List<PendingGroupInvitationResponse> listPendingInvitations(UUID inviteeId) {
        List<GroupInvitation> invitations = invitationRepository.findByInviteeIdAndStatusOrderByCreatedAtDesc(
                inviteeId, GroupInvitationStatus.PENDING);
        return invitations.stream().map(this::toPendingResponse).toList();
    }

    @Transactional
    public GroupDetailsResponse acceptInvitation(UUID invitationId, UUID actingUserId) {
        GroupInvitation invitation = requireOwnedPendingInvitation(invitationId, actingUserId);
        invitation.respond(GroupInvitationStatus.ACCEPTED);
        invitationRepository.save(invitation);

        UUID groupId = invitation.getConversationId();
        if (participantRepository.findByConversationIdAndUserId(groupId, actingUserId).isEmpty()) {
            participantRepository.saveAndFlush(new ConversationParticipant(groupId, actingUserId));
        }
        User user = findUser(actingUserId);
        ChatEvent joined = ChatEvent.of("MEMBER_JOINED", new MemberJoinedPayload(actingUserId, user.getUsername()));
        AfterCommit.run(() -> messagingTemplate.convertAndSend("/topic/chats/" + groupId, joined));
        notifyResolved(invitation, true);
        return details(conversationRepository.findById(groupId).orElseThrow());
    }

    @Transactional
    public void declineInvitation(UUID invitationId, UUID actingUserId) {
        GroupInvitation invitation = requireOwnedPendingInvitation(invitationId, actingUserId);
        invitation.respond(GroupInvitationStatus.DECLINED);
        invitationRepository.save(invitation);
        notifyResolved(invitation, false);
    }

    private void notifyResolved(GroupInvitation invitation, boolean accepted) {
        ChatEvent event =
                ChatEvent.of("INVITATION_RESOLVED", new InvitationResolvedPayload(invitation.getId(), "GROUP", accepted));
        AfterCommit.run(() -> {
            messagingTemplate.convertAndSend("/topic/users/" + invitation.getInviteeId() + "/invitations", event);
            messagingTemplate.convertAndSend("/topic/users/" + invitation.getInviterId() + "/invitations", event);
        });
    }

    // ---- helpers ----

    /** Unique, existing, non-self ids that are all the inviter's contacts - anything else is a 400. */
    private Set<UUID> validatedInvitees(UUID inviterId, List<UUID> ids) {
        Set<UUID> unique = new LinkedHashSet<>(ids == null ? List.of() : ids);
        for (UUID id : unique) {
            if (id == null) {
                throw new InvalidGroupOperationException("Invalid invitee");
            }
            if (id.equals(inviterId)) {
                throw new InvalidGroupOperationException("You can't invite yourself");
            }
            if (!contactService.areContacts(inviterId, id)) {
                throw new InvalidGroupOperationException("You can only invite your own contacts");
            }
        }
        return unique;
    }

    private void createInvitation(Conversation group, UUID inviterId, UUID inviteeId) {
        GroupInvitation invitation =
                invitationRepository.saveAndFlush(new GroupInvitation(group.getId(), inviterId, inviteeId));
        // Pushed straight to the invitee's open app (their personal
        // invitations topic), so it shows up without a refresh.
        messagingTemplate.convertAndSend(
                "/topic/users/" + inviteeId + "/invitations",
                ChatEvent.of("NEW_GROUP_INVITATION", toPendingResponse(invitation)));
    }

    private PendingGroupInvitationResponse toPendingResponse(GroupInvitation invitation) {
        Conversation group = conversationRepository.findById(invitation.getConversationId()).orElseThrow();
        int memberCount = participantRepository.findByConversationId(group.getId()).size();
        return new PendingGroupInvitationResponse(
                invitation.getId(),
                group.getId(),
                group.getName(),
                memberCount,
                ContactUserSummary.from(findUser(invitation.getInviterId())),
                invitation.getCreatedAt());
    }

    private GroupInvitation requireOwnedPendingInvitation(UUID invitationId, UUID actingUserId) {
        GroupInvitation invitation = invitationRepository
                .findById(invitationId)
                .orElseThrow(() -> new NoSuchElementException("Invitation not found"));
        if (!invitation.getInviteeId().equals(actingUserId)) {
            throw new NotInvitationRecipientException();
        }
        if (invitation.getStatus() != GroupInvitationStatus.PENDING) {
            throw new InvitationAlreadyProcessedException();
        }
        return invitation;
    }

    /** Same 404 for "no such group" and "not a member", so a group's existence is never revealed to outsiders. */
    private Conversation requireGroupMember(UUID groupId, UUID userId) {
        Conversation conversation =
                conversationRepository.findById(groupId).orElseThrow(() -> new NoSuchElementException("Group not found"));
        boolean member = conversation.isGroup()
                && participantRepository.findByConversationIdAndUserId(groupId, userId).isPresent();
        if (!member) {
            throw new NoSuchElementException("Group not found");
        }
        return conversation;
    }

    private GroupDetailsResponse details(Conversation group) {
        List<ConversationParticipant> participants = participantRepository.findByConversationId(group.getId());
        Map<UUID, User> users = userRepository
                .findAllById(participants.stream().map(ConversationParticipant::getUserId).toList())
                .stream()
                .collect(Collectors.toMap(User::getId, u -> u));

        List<GroupMemberResponse> members = new ArrayList<>();
        for (ConversationParticipant participant : participants) {
            members.add(new GroupMemberResponse(
                    ContactUserSummary.from(users.get(participant.getUserId())),
                    participant.getRole().name(),
                    participant.getJoinedAt()));
        }
        members.sort(Comparator.comparing(GroupMemberResponse::joinedAt));

        List<ContactUserSummary> pending = invitationRepository
                .findByConversationIdAndStatus(group.getId(), GroupInvitationStatus.PENDING)
                .stream()
                .map(invitation -> ContactUserSummary.from(findUser(invitation.getInviteeId())))
                .toList();

        return new GroupDetailsResponse(
                group.getId(), group.getName(), group.getCreatedBy(), group.getCreatedAt(), members, pending);
    }

    private User findUser(UUID userId) {
        return userRepository.findById(userId).orElseThrow(() -> new NoSuchElementException("User not found"));
    }
}
