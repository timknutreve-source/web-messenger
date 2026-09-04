package com.mobilemessenger.backend.auth;

import com.mobilemessenger.backend.auth.exception.InvalidOrExpiredTokenException;
import com.mobilemessenger.backend.auth.token.PasswordResetToken;
import com.mobilemessenger.backend.auth.token.PasswordResetTokenRepository;
import com.mobilemessenger.backend.auth.token.SecureTokenGenerator;
import com.mobilemessenger.backend.auth.token.VerificationLinks;
import com.mobilemessenger.backend.email.EmailService;
import com.mobilemessenger.backend.user.User;
import com.mobilemessenger.backend.user.UserRepository;
import java.time.Duration;
import java.time.Instant;
import java.util.Locale;
import java.util.NoSuchElementException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class PasswordResetService {

    private static final Logger log = LoggerFactory.getLogger(PasswordResetService.class);
    private static final Duration TOKEN_TTL = Duration.ofHours(1);

    private final PasswordResetTokenRepository tokenRepository;
    private final UserRepository userRepository;
    private final EmailService emailService;
    private final PasswordEncoder passwordEncoder;
    private final String frontendBaseUrl;

    public PasswordResetService(
            PasswordResetTokenRepository tokenRepository,
            UserRepository userRepository,
            EmailService emailService,
            PasswordEncoder passwordEncoder,
            @Value("${app.frontend-base-url}") String frontendBaseUrl) {
        this.tokenRepository = tokenRepository;
        this.userRepository = userRepository;
        this.emailService = emailService;
        this.passwordEncoder = passwordEncoder;
        this.frontendBaseUrl = frontendBaseUrl;
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

    @Transactional
    public void resetPassword(String rawToken, String newPassword) {
        PasswordResetToken token = tokenRepository.findByTokenHash(SecureTokenGenerator.hash(rawToken))
                .orElseThrow(InvalidOrExpiredTokenException::new);

        if (!token.isValid(Instant.now())) {
            throw new InvalidOrExpiredTokenException();
        }

        User user = userRepository.findById(token.getUserId())
                .orElseThrow(() -> new NoSuchElementException("User not found"));
        user.setPasswordHash(passwordEncoder.encode(newPassword));
        userRepository.save(user);

        token.setUsedAt(Instant.now());
        tokenRepository.save(token);
    }

    private void createAndSendResetToken(User user) {
        tokenRepository.deleteByUserIdAndUsedAtIsNull(user.getId());

        String rawToken = SecureTokenGenerator.generate();
        PasswordResetToken token = new PasswordResetToken(
                user.getId(), SecureTokenGenerator.hash(rawToken), Instant.now().plus(TOKEN_TTL));
        tokenRepository.save(token);

        String link = VerificationLinks.resetPasswordLink(frontendBaseUrl, rawToken);
        try {
            emailService.sendPasswordResetEmail(user.getEmail(), user.getUsername(), link);
        } catch (Exception e) {
            log.warn("Failed to send password reset email to user {}: {}", user.getId(), e.getMessage());
        }
    }
}
