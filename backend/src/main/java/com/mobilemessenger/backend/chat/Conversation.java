package com.mobilemessenger.backend.chat;

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
 * A direct (1:1) conversation between two users. {@code directUserAId} and
 * {@code directUserBId} are an ordered pair (a &lt; b) rather than plain
 * "user1/user2" columns so a single partial unique index can guarantee at
 * most one direct conversation per unordered pair of users - see
 * V5__add_conversations.sql.
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

    public UUID getId() { return id; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getLastActivityAt() { return lastActivityAt; }
    public UUID getDirectUserAId() { return directUserAId; }
    public UUID getDirectUserBId() { return directUserBId; }

    /** Returns whichever of the two direct participants is not {@code userId}. */
    public UUID otherUserId(UUID userId) {
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
