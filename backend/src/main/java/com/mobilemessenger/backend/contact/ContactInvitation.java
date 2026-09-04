package com.mobilemessenger.backend.contact;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;
import org.hibernate.annotations.CreationTimestamp;

/**
 * A chat invitation from one user to another. {@code sender}/{@code recipient}
 * are plain user-id columns (no JPA relationship), matching this codebase's
 * existing convention (see {@code EmailVerificationToken}, {@code Contact}).
 */
@Entity
@Table(name = "contact_invitations")
public class ContactInvitation {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "sender_id", nullable = false)
    private UUID senderId;

    @Column(name = "recipient_id", nullable = false)
    private UUID recipientId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private ContactInvitationStatus status;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "responded_at")
    private Instant respondedAt;

    protected ContactInvitation() {
        // for JPA
    }

    public ContactInvitation(UUID senderId, UUID recipientId) {
        this.senderId = senderId;
        this.recipientId = recipientId;
        this.status = ContactInvitationStatus.PENDING;
    }

    public UUID getId() {
        return id;
    }

    public UUID getSenderId() {
        return senderId;
    }

    public UUID getRecipientId() {
        return recipientId;
    }

    public ContactInvitationStatus getStatus() {
        return status;
    }

    public void setStatus(ContactInvitationStatus status) {
        this.status = status;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getRespondedAt() {
        return respondedAt;
    }

    public void setRespondedAt(Instant respondedAt) {
        this.respondedAt = respondedAt;
    }
}
