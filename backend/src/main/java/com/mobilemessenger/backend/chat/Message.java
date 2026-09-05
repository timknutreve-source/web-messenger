package com.mobilemessenger.backend.chat;

import jakarta.persistence.Column;
import jakarta.persistence.Convert;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import com.mobilemessenger.backend.security.encryption.EncryptedStringConverter;
import java.time.Instant;
import java.util.UUID;
import org.hibernate.annotations.CreationTimestamp;

/**
 * A single text message within a conversation. {@code conversationId}/
 * {@code senderId} are plain id columns (no JPA relationship), matching this
 * codebase's existing convention (see {@code Contact}, {@code Conversation}).
 *
 * <p>{@code content} is application-level encrypted at rest (see {@link
 * EncryptedStringConverter}) - this is the core threat this phase defends
 * against: a direct inspection of the {@code messages} table must never
 * reveal message text. Encryption happens transparently at the entity <->
 * column boundary, so every other message feature (chat-list previews,
 * edit, delete, pagination) needs no changes: {@code message.getContent()}
 * already returns plaintext to its caller.
 */
@Entity
@Table(name = "messages")
public class Message {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "conversation_id", nullable = false)
    private UUID conversationId;

    @Column(name = "sender_id", nullable = false)
    private UUID senderId;

    @Convert(converter = EncryptedStringConverter.class)
    @Column(nullable = false, columnDefinition = "TEXT")
    private String content;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private MessageStatus status;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "edited_at")
    private Instant editedAt;

    @Column(name = "deleted_at")
    private Instant deletedAt;

    protected Message() {
        // for JPA
    }

    public Message(UUID conversationId, UUID senderId, String content) {
        this.conversationId = conversationId;
        this.senderId = senderId;
        this.content = content;
        this.status = MessageStatus.SENT;
    }

    public UUID getId() { return id; }
    public UUID getConversationId() { return conversationId; }
    public UUID getSenderId() { return senderId; }
    public String getContent() { return content; }
    public MessageStatus getStatus() { return status; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getEditedAt() { return editedAt; }
    public Instant getDeletedAt() { return deletedAt; }

    public boolean isDeleted() {
        return deletedAt != null;
    }

    public void edit(String newContent) {
        this.content = newContent;
        this.editedAt = Instant.now();
    }

    /** Clears the stored content so the original text can never be re-read once deleted. */
    public void softDelete() {
        this.content = "";
        this.deletedAt = Instant.now();
    }

    public void markDelivered() {
        if (status == MessageStatus.SENT) {
            status = MessageStatus.DELIVERED;
        }
    }

    public void markRead() {
        status = MessageStatus.READ;
    }
}
