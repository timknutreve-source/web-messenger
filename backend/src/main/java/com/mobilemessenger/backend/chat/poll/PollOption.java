package com.mobilemessenger.backend.chat.poll;

import com.mobilemessenger.backend.security.encryption.EncryptedStringConverter;
import jakarta.persistence.Column;
import jakarta.persistence.Convert;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.util.UUID;

@Entity
@Table(name = "poll_options")
public class PollOption {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "poll_id", nullable = false)
    private UUID pollId;

    @Column(nullable = false)
    private int position;

    /** Application-level encrypted at rest, like message text. */
    @Convert(converter = EncryptedStringConverter.class)
    @Column(nullable = false, columnDefinition = "TEXT")
    private String text;

    protected PollOption() {
        // for JPA
    }

    public PollOption(UUID pollId, int position, String text) {
        this.pollId = pollId;
        this.position = position;
        this.text = text;
    }

    public UUID getId() { return id; }
    public UUID getPollId() { return pollId; }
    public int getPosition() { return position; }
    public String getText() { return text; }
}
