package com.mobilemessenger.backend.contact;

import com.mobilemessenger.backend.contact.dto.ContactInvitationResponse;
import com.mobilemessenger.backend.contact.dto.ContactUserSummary;
import com.mobilemessenger.backend.contact.dto.PendingInvitationResponse;
import com.mobilemessenger.backend.contact.exception.AlreadyContactsException;
import com.mobilemessenger.backend.contact.exception.DuplicateInvitationException;
import com.mobilemessenger.backend.contact.exception.InvitationAlreadyProcessedException;
import com.mobilemessenger.backend.contact.exception.NotInvitationRecipientException;
import com.mobilemessenger.backend.contact.exception.SelfInvitationException;
import com.mobilemessenger.backend.user.User;
import com.mobilemessenger.backend.user.UserRepository;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Collectors;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ContactInvitationService {

    private final ContactInvitationRepository invitationRepository;
    private final UserRepository userRepository;
    private final ContactService contactService;

    public ContactInvitationService(
            ContactInvitationRepository invitationRepository,
            UserRepository userRepository,
            ContactService contactService) {
        this.invitationRepository = invitationRepository;
        this.userRepository = userRepository;
        this.contactService = contactService;
    }

    /**
     * Sends an invitation from {@code senderId} to {@code recipientId}.
     *
     * <p>Reverse-direction handling: if {@code recipientId} already has a
     * pending invitation addressed to {@code senderId}, this is treated as
     * accepting that existing invitation instead of creating a second,
     * conflicting one - two people inviting each other at (roughly) the same
     * time become contacts immediately, which matches user expectations
     * better than either a duplicate-invitation error or two independently
     * pending invitations.
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

        Optional<ContactInvitation> reverse = invitationRepository.findBySenderIdAndRecipientIdAndStatus(
                recipientId, senderId, ContactInvitationStatus.PENDING);
        if (reverse.isPresent()) {
            return acceptInvitation(reverse.get().getId(), senderId);
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
