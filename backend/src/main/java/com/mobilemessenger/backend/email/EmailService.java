package com.mobilemessenger.backend.email;

/**
 * Sends the transactional emails the auth flow needs. Two implementations
 * exist: {@link SmtpEmailService} (production, real SMTP) and
 * {@link LoggingEmailService} (local development, logs the link instead of
 * sending it) - selected via the {@code app.email.provider} property. Tests
 * use a third, in-memory implementation so they can inspect what would have
 * been sent without any real network call.
 */
public interface EmailService {

    void sendVerificationEmail(String toEmail, String username, String verificationLink);

    void sendPasswordResetEmail(String toEmail, String username, String resetLink);
}
