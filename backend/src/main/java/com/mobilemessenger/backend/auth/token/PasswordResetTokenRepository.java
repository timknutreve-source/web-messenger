package com.mobilemessenger.backend.auth.token;

import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface PasswordResetTokenRepository extends JpaRepository<PasswordResetToken, UUID> {

    /**
     * The user's single pending (unused) code, if any - {@link
     * com.mobilemessenger.backend.auth.PasswordResetService} always deletes
     * any previous unused code before creating a new one, so there is never
     * more than one per user.
     */
    Optional<PasswordResetToken> findByUserIdAndUsedAtIsNull(UUID userId);

    void deleteByUserIdAndUsedAtIsNull(UUID userId);
}
