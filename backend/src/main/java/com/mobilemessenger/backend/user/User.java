package com.mobilemessenger.backend.user;

import jakarta.persistence.Column;
import jakarta.persistence.Convert;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import com.mobilemessenger.backend.security.encryption.EncryptedStringConverter;
import java.time.Instant;
import java.util.UUID;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

/**
 * A registered account. Shared across features - authentication owns creation
 * and credential checks, the profile feature owns editable account data,
 * later phases (messaging, ...) will reference this entity rather than
 * duplicating user data.
 *
 * <p>{@code aboutMe} is application-level encrypted at rest (see {@link
 * EncryptedStringConverter}) - it is free-text, user-authored profile
 * content, exactly the kind of thing the threat model (someone inspecting
 * the database directly) must not be able to read. {@code username} and
 * {@code email} stay plaintext: both are used for uniqueness constraints,
 * login lookup, and contact search, none of which work against ciphertext
 * without a redesign (a separate searchable hash/token column) that isn't
 * warranted by the current requirements. This entity is never returned
 * directly from a controller - all reads/writes go through {@link
 * UserResponse} and feature-specific request DTOs - so the encrypted column
 * is entirely invisible to callers; {@code user.getAboutMe()} already
 * returns plaintext.
 */
@Entity
@Table(name = "users")
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(nullable = false, unique = true, length = 30)
    private String username;

    @Column(nullable = false, unique = true)
    private String email;

    @Column(name = "password_hash", nullable = false)
    private String passwordHash;

    @Column(name = "email_verified", nullable = false)
    private boolean emailVerified = false;

    @Convert(converter = EncryptedStringConverter.class)
    @Column(name = "about_me", columnDefinition = "TEXT")
    private String aboutMe;

    @Column(name = "avatar_file_name")
    private String avatarFileName;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected User() {
        // for JPA
    }

    public User(String username, String email, String passwordHash) {
        this.username = username;
        this.email = email;
        this.passwordHash = passwordHash;
    }

    public UUID getId() {
        return id;
    }

    public String getUsername() {
        return username;
    }

    public void setUsername(String username) {
        this.username = username;
    }

    public String getEmail() {
        return email;
    }

    public void setEmail(String email) {
        this.email = email;
    }

    public String getPasswordHash() {
        return passwordHash;
    }

    public void setPasswordHash(String passwordHash) {
        this.passwordHash = passwordHash;
    }

    public boolean isEmailVerified() {
        return emailVerified;
    }

    public void setEmailVerified(boolean emailVerified) {
        this.emailVerified = emailVerified;
    }

    public String getAboutMe() {
        return aboutMe;
    }

    public void setAboutMe(String aboutMe) {
        this.aboutMe = aboutMe;
    }

    public String getAvatarFileName() {
        return avatarFileName;
    }

    public void setAvatarFileName(String avatarFileName) {
        this.avatarFileName = avatarFileName;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }
}
