package com.mobilemessenger.backend.chat;

import com.mobilemessenger.backend.security.encryption.EncryptedStringConverter;
import jakarta.persistence.Column;
import jakarta.persistence.Convert;
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
 * A conversation: either DIRECT (1:1 between two users) or a named GROUP.
 *
 * <p>For a direct conversation, {@code directUserAId} and {@code
 * directUserBId} are an ordered pair (a &lt; b) rather than plain
 * "user1/user2" columns so a single partial unique index can guarantee at
 * most one direct conversation per unordered pair of users - see
 * V5__add_conversations.sql. A group leaves both null; its members are just
 * its {@link ConversationParticipant} rows, and its {@code name} (chat-list
 * content, so encrypted at rest like message text) identifies it.
 */
@Entity
@Table(name = "conversations")
public class Conversation {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "last_activity_at", nullable = false)
    private Instant lastActivityAt;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 10)
    private ConversationType type = ConversationType.DIRECT;

    @Convert(converter = EncryptedStringConverter.class)
    @Column(columnDefinition = "TEXT")
    private String name;

    @Column(name = "created_by")
    private UUID createdBy;

    @Column(name = "direct_user_a_id")
    private UUID directUserAId;

    @Column(name = "direct_user_b_id")
    private UUID directUserBId;

    protected Conversation() {
        // for JPA
    }

    /** {@code userIdA}/{@code userIdB} must already be ordered (a &lt; b). */
    public Conversation(UUID userIdA, UUID userIdB) {
        this.directUserAId = userIdA;
        this.directUserBId = userIdB;
        this.lastActivityAt = Instant.now();
    }

    /** A new group conversation, named {@code name} and created by {@code createdBy}. */
    public static Conversation newGroup(String name, UUID createdBy) {
        Conversation conversation = new Conversation();
        conversation.type = ConversationType.GROUP;
        conversation.name = name;
        conversation.createdBy = createdBy;
        conversation.lastActivityAt = Instant.now();
        return conversation;
    }

    public UUID getId() { return id; }
    public ConversationType getType() { return type; }
    public boolean isGroup() { return type == ConversationType.GROUP; }
    public String getName() { return name; }
    public UUID getCreatedBy() { return createdBy; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getLastActivityAt() { return lastActivityAt; }
    public UUID getDirectUserAId() { return directUserAId; }
    public UUID getDirectUserBId() { return directUserBId; }

    /** Returns whichever of the two direct participants is not {@code userId}. Direct conversations only. */
    public UUID otherUserId(UUID userId) {
        if (isGroup()) {
            throw new IllegalStateException("A group conversation has no single 'other' user");
        }
        return directUserAId.equals(userId) ? directUserBId : directUserAId;
    }

    /**
     * Bumps {@code lastActivityAt}. Not called anywhere yet in Phase 6 (there
     * are no messages), but the chat list is required to sort by this field
     * once Phase 7 starts calling it on every new message.
     */
    public void touchActivity(Instant at) {
        this.lastActivityAt = at;
    }
}
