package com.mobilemessenger.backend.auth;

import com.mobilemessenger.backend.auth.exception.InvalidOrExpiredTokenException;
import com.mobilemessenger.backend.auth.token.PasswordResetToken;
import com.mobilemessenger.backend.auth.token.PasswordResetTokenRepository;
import com.mobilemessenger.backend.auth.token.SecureTokenGenerator;
import com.mobilemessenger.backend.email.EmailService;
import com.mobilemessenger.backend.user.User;
import com.mobilemessenger.backend.user.UserRepository;
import java.time.Duration;
import java.time.Instant;
import java.util.Locale;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class PasswordResetService {

    private static final Logger log = LoggerFactory.getLogger(PasswordResetService.class);
    private static final Duration CODE_TTL = Duration.ofHours(1);

    /** See {@link EmailVerificationService#MAX_ATTEMPTS} for the rationale. */
    private static final int MAX_ATTEMPTS = 5;

    private final PasswordResetTokenRepository tokenRepository;
    private final UserRepository userRepository;
    private final EmailService emailService;
    private final PasswordEncoder passwordEncoder;

    public PasswordResetService(
            PasswordResetTokenRepository tokenRepository,
            UserRepository userRepository,
            EmailService emailService,
            PasswordEncoder passwordEncoder) {
        this.tokenRepository = tokenRepository;
        this.userRepository = userRepository;
        this.emailService = emailService;
        this.passwordEncoder = passwordEncoder;
    }

    /**
     * Requests a password reset for {@code rawEmail}. Deliberately never
     * throws or otherwise signals whether the address is registered - if it
     * isn't, this is a silent no-op, so the caller's response is identical
     * either way.
     */
    @Transactional
    public void requestPasswordReset(String rawEmail) {
        String email = rawEmail.trim().toLowerCase(Locale.ROOT);
        userRepository.findByEmail(email).ifPresent(this::createAndSendResetToken);
    }

    /**
     * Resets the password for the account identified by {@code rawEmail},
     * if {@code rawCode} matches its currently pending reset code. An
     * unknown email and a wrong/expired/exhausted code all fail identically
     * (see {@link InvalidOrExpiredTokenException}), so this never reveals
     * whether the address is registered - the same enumeration-safety
     * {@link #requestPasswordReset} already provides.
     */
    @Transactional
    public void resetPassword(String rawEmail, String rawCode, String newPassword) {
        String email = rawEmail.trim().toLowerCase(Locale.ROOT);
        User user = userRepository.findByEmail(email)
                .orElseThrow(InvalidOrExpiredTokenException::new);

        PasswordResetToken token = tokenRepository.findByUserIdAndUsedAtIsNull(user.getId())
                .orElseThrow(InvalidOrExpiredTokenException::new);

        if (!token.isValid(Instant.now()) || token.getAttempts() >= MAX_ATTEMPTS) {
            throw new InvalidOrExpiredTokenException();
        }

        if (!SecureTokenGenerator.hashesMatch(token.getTokenHash(), SecureTokenGenerator.hash(rawCode))) {
            token.incrementAttempts();
            tokenRepository.save(token);
            throw new InvalidOrExpiredTokenException();
        }

        user.setPasswordHash(passwordEncoder.encode(newPassword));
        userRepository.save(user);

        token.setUsedAt(Instant.now());
        tokenRepository.save(token);
    }

    private void createAndSendResetToken(User user) {
        tokenRepository.deleteByUserIdAndUsedAtIsNull(user.getId());

        String rawCode = SecureTokenGenerator.generateNumericCode();
        PasswordResetToken token = new PasswordResetToken(
                user.getId(), SecureTokenGenerator.hash(rawCode), Instant.now().plus(CODE_TTL));
        tokenRepository.save(token);

        try {
            emailService.sendPasswordResetEmail(user.getEmail(), user.getUsername(), rawCode);
        } catch (Exception e) {
            log.warn("Failed to send password reset email to user {}: {}", user.getId(), e.getMessage());
        }
    }
}
