package com.mobilemessenger.backend.chat.group;

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
 * An invitation to join a group. Membership is created only by the invitee
 * accepting it - see V11__group_conversations.sql.
 */
@Entity
@Table(name = "group_invitations")
public class GroupInvitation {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "conversation_id", nullable = false)
    private UUID conversationId;

    @Column(name = "inviter_id", nullable = false)
    private UUID inviterId;

    @Column(name = "invitee_id", nullable = false)
    private UUID inviteeId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 10)
    private GroupInvitationStatus status = GroupInvitationStatus.PENDING;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "responded_at")
    private Instant respondedAt;

    protected GroupInvitation() {
        // for JPA
    }

    public GroupInvitation(UUID conversationId, UUID inviterId, UUID inviteeId) {
        this.conversationId = conversationId;
        this.inviterId = inviterId;
        this.inviteeId = inviteeId;
    }

    public UUID getId() { return id; }
    public UUID getConversationId() { return conversationId; }
    public UUID getInviterId() { return inviterId; }
    public UUID getInviteeId() { return inviteeId; }
    public GroupInvitationStatus getStatus() { return status; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getRespondedAt() { return respondedAt; }

    public void respond(GroupInvitationStatus newStatus) {
        this.status = newStatus;
        this.respondedAt = Instant.now();
    }
}
