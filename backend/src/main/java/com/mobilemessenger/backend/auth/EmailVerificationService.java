package com.mobilemessenger.backend.auth;

import com.mobilemessenger.backend.auth.exception.EmailAlreadyVerifiedException;
import com.mobilemessenger.backend.auth.exception.InvalidOrExpiredTokenException;
import com.mobilemessenger.backend.auth.token.EmailVerificationToken;
import com.mobilemessenger.backend.auth.token.EmailVerificationTokenRepository;
import com.mobilemessenger.backend.auth.token.SecureTokenGenerator;
import com.mobilemessenger.backend.auth.token.VerificationLinks;
import com.mobilemessenger.backend.email.EmailService;
import com.mobilemessenger.backend.user.User;
import com.mobilemessenger.backend.user.UserRepository;
import java.time.Duration;
import java.time.Instant;
import java.util.NoSuchElementException;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class EmailVerificationService {

    private static final Logger log = LoggerFactory.getLogger(EmailVerificationService.class);
    private static final Duration TOKEN_TTL = Duration.ofHours(24);

    private final EmailVerificationTokenRepository tokenRepository;
    private final UserRepository userRepository;
    private final EmailService emailService;
    private final String frontendBaseUrl;

    public EmailVerificationService(
            EmailVerificationTokenRepository tokenRepository,
            UserRepository userRepository,
            EmailService emailService,
            @Value("${app.frontend-base-url}") String frontendBaseUrl) {
        this.tokenRepository = tokenRepository;
        this.userRepository = userRepository;
        this.emailService = emailService;
        this.frontendBaseUrl = frontendBaseUrl;
    }

    /**
     * Creates a fresh verification token for {@code user}, invalidating any
     * previous unused one, and emails the link. Registration calls this
     * directly; {@link #resendVerification} calls it after checking the
     * account isn't already verified.
     */
    @Transactional
    public void createAndSendVerificationToken(User user) {
        tokenRepository.deleteByUserIdAndUsedAtIsNull(user.getId());

        String rawToken = SecureTokenGenerator.generate();
        EmailVerificationToken token = new EmailVerificationToken(
                user.getId(), SecureTokenGenerator.hash(rawToken), Instant.now().plus(TOKEN_TTL));
        tokenRepository.save(token);

        String link = VerificationLinks.verifyEmailLink(frontendBaseUrl, rawToken);
        try {
            emailService.sendVerificationEmail(user.getEmail(), user.getUsername(), link);
        } catch (Exception e) {
            // The token still exists and can be resent later - registration
            // (or a resend request) shouldn't fail just because the mail
            // provider is temporarily unreachable.
            log.warn("Failed to send verification email to user {}: {}", user.getId(), e.getMessage());
        }
    }

    @Transactional
    public void verifyEmail(String rawToken) {
        EmailVerificationToken token = tokenRepository.findByTokenHash(SecureTokenGenerator.hash(rawToken))
                .orElseThrow(InvalidOrExpiredTokenException::new);

        if (!token.isValid(Instant.now())) {
            throw new InvalidOrExpiredTokenException();
        }

        User user = userRepository.findById(token.getUserId())
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
