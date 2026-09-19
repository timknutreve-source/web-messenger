package com.mobilemessenger.backend.chat.poll;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

/** One user's single vote in one poll; changing the vote updates this row, retracting deletes it. */
@Entity
@Table(name = "poll_votes")
public class PollVote {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "poll_id", nullable = false)
    private UUID pollId;

    @Column(name = "option_id", nullable = false)
    private UUID optionId;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "voted_at", nullable = false)
    private Instant votedAt;

    protected PollVote() {
        // for JPA
    }

    public PollVote(UUID pollId, UUID optionId, UUID userId) {
        this.pollId = pollId;
        this.optionId = optionId;
        this.userId = userId;
        this.votedAt = Instant.now();
    }

    public UUID getPollId() { return pollId; }
    public UUID getOptionId() { return optionId; }
    public UUID getUserId() { return userId; }
    public Instant getVotedAt() { return votedAt; }

    public void changeTo(UUID newOptionId) {
        this.optionId = newOptionId;
        this.votedAt = Instant.now();
    }
}
