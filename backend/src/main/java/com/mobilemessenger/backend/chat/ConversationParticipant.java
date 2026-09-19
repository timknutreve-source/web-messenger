package com.mobilemessenger.backend.chat;

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
 * One user's membership in a conversation, including their own archive
 * state. Archiving is per-user (see V5__add_conversations.sql), so this
 * lives on the participant row rather than on {@link Conversation} itself.
 */
@Entity
@Table(name = "conversation_participants")
public class ConversationParticipant {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "conversation_id", nullable = false)
    private UUID conversationId;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 10)
    private ParticipantRole role = ParticipantRole.MEMBER;

    @Column(nullable = false)
    private boolean archived;

    @Column(name = "archived_at")
    private Instant archivedAt;

    @CreationTimestamp
    @Column(name = "joined_at", nullable = false, updatable = false)
    private Instant joinedAt;

    protected ConversationParticipant() {
        // for JPA
    }

    public ConversationParticipant(UUID conversationId, UUID userId) {
        this.conversationId = conversationId;
        this.userId = userId;
        this.archived = false;
    }

    public ConversationParticipant(UUID conversationId, UUID userId, ParticipantRole role) {
        this(conversationId, userId);
        this.role = role;
    }

    public ParticipantRole getRole() { return role; }
    public UUID getId() { return id; }
    public UUID getConversationId() { return conversationId; }
    public UUID getUserId() { return userId; }
    public boolean isArchived() { return archived; }
    public Instant getArchivedAt() { return archivedAt; }
    public Instant getJoinedAt() { return joinedAt; }

    public void archive() {
        this.archived = true;
        this.archivedAt = Instant.now();
    }

    public void unarchive() {
        this.archived = false;
        this.archivedAt = null;
    }
}
