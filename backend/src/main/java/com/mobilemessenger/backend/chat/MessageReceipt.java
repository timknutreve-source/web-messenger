package com.mobilemessenger.backend.chat;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

/**
 * Whether one specific recipient has received and/or read one group message.
 * A direct chat has a single recipient and keeps using {@link Message#getStatus()}
 * alone; a group message has many, so its status is derived from these rows -
 * see {@link GroupReceiptService}.
 */
@Entity
@Table(name = "message_receipts")
public class MessageReceipt {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "message_id", nullable = false)
    private UUID messageId;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "delivered_at")
    private Instant deliveredAt;

    @Column(name = "read_at")
    private Instant readAt;

    protected MessageReceipt() {
        // for JPA
    }

    public MessageReceipt(UUID messageId, UUID userId) {
        this.messageId = messageId;
        this.userId = userId;
    }

    public UUID getMessageId() { return messageId; }
    public UUID getUserId() { return userId; }
    public Instant getDeliveredAt() { return deliveredAt; }
    public Instant getReadAt() { return readAt; }

    public void markDelivered(Instant at) {
        if (deliveredAt == null) {
            deliveredAt = at;
        }
    }

    /** Reading a message implies it was delivered. */
    public void markRead(Instant at) {
        markDelivered(at);
        if (readAt == null) {
            readAt = at;
        }
    }

    public boolean isDelivered() {
        return deliveredAt != null;
    }

    public boolean isRead() {
        return readAt != null;
    }
}
