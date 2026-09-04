package com.mobilemessenger.backend.contact;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ContactInvitationRepository extends JpaRepository<ContactInvitation, UUID> {

    Optional<ContactInvitation> findBySenderIdAndRecipientIdAndStatus(
            UUID senderId, UUID recipientId, ContactInvitationStatus status);

    List<ContactInvitation> findByRecipientIdAndStatusOrderByCreatedAtDesc(
            UUID recipientId, ContactInvitationStatus status);
}
