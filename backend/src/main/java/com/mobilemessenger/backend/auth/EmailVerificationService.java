package com.mobilemessenger.backend.auth;

import com.mobilemessenger.backend.auth.exception.EmailAlreadyVerifiedException;
import com.mobilemessenger.backend.auth.exception.InvalidOrExpiredTokenException;
import com.mobilemessenger.backend.auth.token.EmailVerificationToken;
import com.mobilemessenger.backend.auth.token.EmailVerificationTokenRepository;
import com.mobilemessenger.backend.auth.token.SecureTokenGenerator;
import com.mobilemessenger.backend.email.EmailService;
import com.mobilemessenger.backend.user.User;
import com.mobilemessenger.backend.user.UserRepository;
import java.time.Duration;
import java.time.Instant;
import java.util.NoSuchElementException;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class EmailVerificationService {

    private static final Logger log = LoggerFactory.getLogger(EmailVerificationService.class);
    private static final Duration CODE_TTL = Duration.ofHours(24);

    /**
     * A 6-digit code has a far smaller guessing space than the old 256-bit
     * token, so unlike that token this needs an explicit limit on how many
     * wrong guesses a single pending code tolerates before it's treated as
     * invalid - forcing a fresh code (and fresh attempt count) via resend.
     */
    private static final int MAX_ATTEMPTS = 5;

    private final EmailVerificationTokenRepository tokenRepository;
    private final UserRepository userRepository;
    private final EmailService emailService;

    public EmailVerificationService(
            EmailVerificationTokenRepository tokenRepository,
            UserRepository userRepository,
            EmailService emailService) {
        this.tokenRepository = tokenRepository;
        this.userRepository = userRepository;
        this.emailService = emailService;
    }

    /**
     * Creates a fresh verification code for {@code user}, invalidating any
     * previous unused one, and emails it. Registration calls this directly;
     * {@link #resendVerification} calls it after checking the account isn't
     * already verified.
     */
    @Transactional
    public void createAndSendVerificationToken(User user) {
        tokenRepository.deleteByUserIdAndUsedAtIsNull(user.getId());

        String rawCode = SecureTokenGenerator.generateNumericCode();
        EmailVerificationToken token = new EmailVerificationToken(
                user.getId(), SecureTokenGenerator.hash(rawCode), Instant.now().plus(CODE_TTL));
        tokenRepository.save(token);

        try {
            emailService.sendVerificationEmail(user.getEmail(), user.getUsername(), rawCode);
        } catch (Exception e) {
            // The code still exists and can be resent later - registration
            // (or a resend request) shouldn't fail just because the mail
            // provider is temporarily unreachable.
            log.warn("Failed to send verification email to user {}: {}", user.getId(), e.getMessage());
        }
    }

    /**
     * Verifies {@code userId}'s pending code. Scoped to the authenticated
     * user (rather than looking the code up globally, as the old link-based
     * token did) because a 6-digit code alone isn't unique enough across
     * accounts to identify who it belongs to.
     */
    @Transactional
    public void verifyEmail(UUID userId, String rawCode) {
        EmailVerificationToken token = tokenRepository.findByUserIdAndUsedAtIsNull(userId)
                .orElseThrow(InvalidOrExpiredTokenException::new);

        if (!token.isValid(Instant.now()) || token.getAttempts() >= MAX_ATTEMPTS) {
            throw new InvalidOrExpiredTokenException();
        }

        if (!SecureTokenGenerator.hashesMatch(token.getTokenHash(), SecureTokenGenerator.hash(rawCode))) {
            token.incrementAttempts();
            tokenRepository.save(token);
            throw new InvalidOrExpiredTokenException();
        }

        User user = userRepository.findById(userId)
                .orElseThrow(() -> new NoSuchElementException("User not found"));
        user.setEmailVerified(true);
        userRepository.save(user);

        token.setUsedAt(Instant.now());
        tokenRepository.save(token);
    }

    @Transactional
    public void resendVerification(UUID userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new NoSuchElementException("User not found"));
        if (user.isEmailVerified()) {
            throw new EmailAlreadyVerifiedException();
        }
        createAndSendVerificationToken(user);
    }
}
