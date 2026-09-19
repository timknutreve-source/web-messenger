package com.mobilemessenger.backend.chat.poll;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;
import org.hibernate.annotations.CreationTimestamp;

/**
 * A poll in a group chat. It hangs off an ordinary message (whose content is
 * the question), so it appears in the timeline, sorts the chat list, and can
 * be searched and deleted like any other message.
 */
@Entity
@Table(name = "polls")
public class Poll {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "conversation_id", nullable = false)
    private UUID conversationId;

    @Column(name = "message_id", nullable = false, unique = true)
    private UUID messageId;

    @Column(name = "created_by", nullable = false)
    private UUID createdBy;

    @Column(nullable = false)
    private boolean anonymous;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    protected Poll() {
        // for JPA
    }

    public Poll(UUID conversationId, UUID messageId, UUID createdBy, boolean anonymous) {
        this.conversationId = conversationId;
        this.messageId = messageId;
        this.createdBy = createdBy;
        this.anonymous = anonymous;
    }

    public UUID getId() { return id; }
    public UUID getConversationId() { return conversationId; }
    public UUID getMessageId() { return messageId; }
    public UUID getCreatedBy() { return createdBy; }
    public boolean isAnonymous() { return anonymous; }
    public Instant getCreatedAt() { return createdAt; }
}
