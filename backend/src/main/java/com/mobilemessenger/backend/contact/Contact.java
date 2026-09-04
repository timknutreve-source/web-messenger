package com.mobilemessenger.backend.contact;

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
 * One directed "user has contact" row. An accepted invitation creates two of
 * these (A→B and B→A) so that "list my contacts" is a single indexed
 * {@code WHERE user_id = ?} query rather than an OR-across-two-columns scan.
 */
@Entity
@Table(name = "contacts")
public class Contact {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "contact_id", nullable = false)
    private UUID contactId;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    protected Contact() {
        // for JPA
    }

    public Contact(UUID userId, UUID contactId) {
        this.userId = userId;
        this.contactId = contactId;
    }

    public UUID getId() {
        return id;
    }

    public UUID getUserId() {
        return userId;
    }

    public UUID getContactId() {
        return contactId;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
