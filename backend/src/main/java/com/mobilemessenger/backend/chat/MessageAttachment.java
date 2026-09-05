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
 * An uploaded image or video, optionally attached to a {@link Message}.
 *
 * <p>Uploading happens before a message exists to attach it to (the Flutter
 * client uploads the file, gets back an id, then sends the message
 * referencing it) - so {@code messageId} starts {@code null} ("pending") and
 * is set once a message actually consumes it (see {@code MessageService}).
 * {@code conversationId} and {@code uploaderId} are recorded independently
 * of {@code messageId} specifically so a pending attachment can still be
 * authorized (only its uploader may preview or attach it) before it belongs
 * to any message.
 *
 * <p>{@code originalFilename} is application-level encrypted at rest (see
 * {@link EncryptedStringConverter}) - it's user-supplied, user-visible text
 * that can leak information about the attachment's content. {@code
 * storageKey}/{@code thumbnailStorageKey} stay plaintext: they are opaque,
 * server-generated random identifiers ({@code UUID.randomUUID()} plus an
 * extension) with no user data embedded, so encrypting them would add no
 * confidentiality and would only complicate file lookup. {@code type},
 * {@code mimeType}, {@code fileSize}, {@code width}/{@code height}, and
 * {@code durationSeconds} stay plaintext too: low-sensitivity metadata
 * needed for the API response and validation, not the message content
 * itself. The actual file bytes are encrypted separately, at rest on disk -
 * see {@link com.mobilemessenger.backend.storage.LocalFileStorageService}.
 */
@Entity
@Table(name = "message_attachments")
public class MessageAttachment {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "conversation_id", nullable = false)
    private UUID conversationId;

    @Column(name = "message_id")
    private UUID messageId;

    @Column(name = "uploader_id", nullable = false)
    private UUID uploaderId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private AttachmentType type;

    @Column(name = "storage_key", nullable = false, length = 255)
    private String storageKey;

    @Column(name = "thumbnail_storage_key", length = 255)
    private String thumbnailStorageKey;

    @Convert(converter = EncryptedStringConverter.class)
    @Column(name = "original_filename", columnDefinition = "TEXT")
    private String originalFilename;

    @Column(name = "mime_type", nullable = false, length = 100)
    private String mimeType;

    @Column(name = "file_size", nullable = false)
    private long fileSize;

    @Column
    private Integer width;

    @Column
    private Integer height;

    @Column(name = "duration_seconds")
    private Integer durationSeconds;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    protected MessageAttachment() {
        // for JPA
    }

    public MessageAttachment(
            UUID conversationId,
            UUID uploaderId,
            AttachmentType type,
            String storageKey,
            String mimeType,
            long fileSize) {
        this.conversationId = conversationId;
        this.uploaderId = uploaderId;
        this.type = type;
        this.storageKey = storageKey;
        this.mimeType = mimeType;
        this.fileSize = fileSize;
    }

    public UUID getId() { return id; }
    public UUID getConversationId() { return conversationId; }
    public UUID getMessageId() { return messageId; }
    public UUID getUploaderId() { return uploaderId; }
    public AttachmentType getType() { return type; }
    public String getStorageKey() { return storageKey; }
    public String getThumbnailStorageKey() { return thumbnailStorageKey; }
    public String getOriginalFilename() { return originalFilename; }
    public String getMimeType() { return mimeType; }
    public long getFileSize() { return fileSize; }
    public Integer getWidth() { return width; }
    public Integer getHeight() { return height; }
    public Integer getDurationSeconds() { return durationSeconds; }
    public Instant getCreatedAt() { return createdAt; }

    public boolean isPending() {
        return messageId == null;
    }

    /** Consumes this pending attachment into {@code messageId}; a no-op guard against double-attaching. */
    public void attachTo(UUID messageId) {
        this.messageId = messageId;
    }

    public void setThumbnailStorageKey(String thumbnailStorageKey) {
        this.thumbnailStorageKey = thumbnailStorageKey;
    }

    public void setOriginalFilename(String originalFilename) {
        this.originalFilename = originalFilename;
    }

    public void setDimensions(Integer width, Integer height) {
        this.width = width;
        this.height = height;
    }

    public void setDurationSeconds(Integer durationSeconds) {
        this.durationSeconds = durationSeconds;
    }
}
