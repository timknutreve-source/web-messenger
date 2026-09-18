package com.mobilemessenger.backend.contact;

import com.mobilemessenger.backend.chat.ChatService;
import com.mobilemessenger.backend.chat.websocket.ChatEvent;
import com.mobilemessenger.backend.contact.dto.ContactInvitationResponse;
import com.mobilemessenger.backend.contact.dto.ContactUserSummary;
import com.mobilemessenger.backend.contact.dto.PendingInvitationResponse;
import com.mobilemessenger.backend.contact.exception.AlreadyContactsException;
import com.mobilemessenger.backend.contact.exception.DuplicateInvitationException;
import com.mobilemessenger.backend.contact.exception.InvitationAlreadyProcessedException;
import com.mobilemessenger.backend.contact.exception.NotInvitationRecipientException;
import com.mobilemessenger.backend.contact.exception.PendingInvitationFromRecipientException;
import com.mobilemessenger.backend.contact.exception.SelfInvitationException;
import com.mobilemessenger.backend.user.User;
import com.mobilemessenger.backend.user.UserRepository;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;
import java.util.UUID;
import java.util.stream.Collectors;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ContactInvitationService {

    private final ContactInvitationRepository invitationRepository;
    private final UserRepository userRepository;
    private final ContactService contactService;
    private final ChatService chatService;
    private final SimpMessagingTemplate messagingTemplate;

    public ContactInvitationService(
            ContactInvitationRepository invitationRepository,
            UserRepository userRepository,
            ContactService contactService,
            ChatService chatService,
            SimpMessagingTemplate messagingTemplate) {
        this.invitationRepository = invitationRepository;
        this.userRepository = userRepository;
        this.contactService = contactService;
        this.chatService = chatService;
        this.messagingTemplate = messagingTemplate;
    }

    /**
     * Sends an invitation from {@code senderId} to {@code recipientId}.
     *
     * <p>Reverse-direction handling: if {@code recipientId} already has a
     * pending invitation addressed to {@code senderId}, this call is
     * rejected rather than silently accepted on the sender's behalf - a
     * contact relationship must only ever be created by the recipient of an
     * invitation explicitly accepting it (see {@link #acceptInvitation}).
     * The sender is told to respond to the existing invitation instead.
     */
    @Transactional
    public ContactInvitationResponse sendInvitation(UUID senderId, UUID recipientId) {
        if (senderId.equals(recipientId)) {
            throw new SelfInvitationException();
        }

        User sender = findUser(senderId);
        User recipient = findUser(recipientId);

        if (contactService.areContacts(senderId, recipientId)) {
            throw new AlreadyContactsException();
        }

        boolean reversePending = invitationRepository
                .findBySenderIdAndRecipientIdAndStatus(recipientId, senderId, ContactInvitationStatus.PENDING)
                .isPresent();
        if (reversePending) {
            throw new PendingInvitationFromRecipientException();
        }

        boolean alreadyPending = invitationRepository
                .findBySenderIdAndRecipientIdAndStatus(senderId, recipientId, ContactInvitationStatus.PENDING)
                .isPresent();
        if (alreadyPending) {
            throw new DuplicateInvitationException();
        }

        // flush (not just save) so the @CreationTimestamp-generated createdAt,
        // which Hibernate only populates immediately before the INSERT is
        // executed, is actually present on the entity we're about to serialize.
        ContactInvitation invitation =
                invitationRepository.saveAndFlush(new ContactInvitation(senderId, recipientId));

        // Pushes the new invitation to the recipient immediately if their app
        // is open (subscribed to their own personal invitations topic - see
        // ChatSubscriptionInterceptor) - without this, a recipient who is
        // already logged in would only ever see it after their next login or
        // an app restart, since nothing else refreshes their pending list.
        messagingTemplate.convertAndSend(
                "/topic/users/" + recipientId + "/invitations",
                ChatEvent.of("NEW_INVITATION", new PendingInvitationResponse(
                        invitation.getId(), ContactUserSummary.from(sender), invitation.getCreatedAt())));

        return toResponse(invitation, sender, recipient);
    }

    public List<PendingInvitationResponse> listPendingInvitations(UUID recipientId) {
        List<ContactInvitation> invitations = invitationRepository.findByRecipientIdAndStatusOrderByCreatedAtDesc(
                recipientId, ContactInvitationStatus.PENDING);
        if (invitations.isEmpty()) {
            return List.of();
        }

        Map<UUID, User> sendersById = userRepository
                .findAllById(invitations.stream().map(ContactInvitation::getSenderId).toList())
                .stream()
                .collect(Collectors.toMap(User::getId, user -> user));

        return invitations.stream()
                .map(invitation -> new PendingInvitationResponse(
                        invitation.getId(),
                        ContactUserSummary.from(sendersById.get(invitation.getSenderId())),
                        invitation.getCreatedAt()))
                .toList();
    }

    @Transactional
    public ContactInvitationResponse acceptInvitation(UUID invitationId, UUID actingUserId) {
        ContactInvitation invitation = requireOwnedPendingInvitation(invitationId, actingUserId);

        invitation.setStatus(ContactInvitationStatus.ACCEPTED);
        invitation.setRespondedAt(Instant.now());
        invitationRepository.save(invitation);

        contactService.createMutualContact(invitation.getSenderId(), invitation.getRecipientId());
        // Same transaction as the contact creation above, so an accepted
        // invitation always has both a contact relationship and a
        // conversation, or (on failure) neither.
        chatService.getOrCreateDirectConversation(invitation.getSenderId(), invitation.getRecipientId());

        return toResponse(invitation);
    }

    @Transactional
    public ContactInvitationResponse declineInvitation(UUID invitationId, UUID actingUserId) {
        ContactInvitation invitation = requireOwnedPendingInvitation(invitationId, actingUserId);

        invitation.setStatus(ContactInvitationStatus.DECLINED);
        invitation.setRespondedAt(Instant.now());
        invitationRepository.save(invitation);

        return toResponse(invitation);
    }

    /**
     * Loads the invitation and enforces that only its recipient may act on
     * it, and only while it's still pending - the actor's id always comes
     * from the authenticated JWT (see the controller), never from client input.
     */
    private ContactInvitation requireOwnedPendingInvitation(UUID invitationId, UUID actingUserId) {
        ContactInvitation invitation = invitationRepository.findById(invitationId)
                .orElseThrow(() -> new NoSuchElementException("Invitation not found"));

        if (!invitation.getRecipientId().equals(actingUserId)) {
            throw new NotInvitationRecipientException();
        }
        if (invitation.getStatus() != ContactInvitationStatus.PENDING) {
            throw new InvitationAlreadyProcessedException();
        }
        return invitation;
    }

    private User findUser(UUID userId) {
        return userRepository.findById(userId).orElseThrow(() -> new NoSuchElementException("User not found"));
    }

    private ContactInvitationResponse toResponse(ContactInvitation invitation) {
        return toResponse(invitation, findUser(invitation.getSenderId()), findUser(invitation.getRecipientId()));
    }

    private ContactInvitationResponse toResponse(ContactInvitation invitation, User sender, User recipient) {
        return new ContactInvitationResponse(
                invitation.getId(),
                ContactUserSummary.from(sender),
                ContactUserSummary.from(recipient),
                invitation.getStatus().name(),
                invitation.getCreatedAt(),
                invitation.getRespondedAt());
    }
}
