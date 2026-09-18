package com.mobilemessenger.backend.auth.token;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface EmailVerificationTokenRepository extends JpaRepository<EmailVerificationToken, UUID> {

    /**
     * The user's single pending (unused) code, if any - {@link
     * com.mobilemessenger.backend.auth.EmailVerificationService} always
     * deletes any previous unused code before creating a new one, so there
     * is never more than one per user.
     */
    Optional<EmailVerificationToken> findByUserIdAndUsedAtIsNull(UUID userId);

    List<EmailVerificationToken> findByUserId(UUID userId);

    void deleteByUserIdAndUsedAtIsNull(UUID userId);
}
