package com.mobilemessenger.backend.email;

/**
 * Sends the transactional emails the auth flow needs. Two implementations
 * exist: {@link SmtpEmailService} (production, real SMTP) and
 * {@link LoggingEmailService} (local development, logs the code instead of
 * sending it) - selected via the {@code app.email.provider} property. Tests
 * use a third, in-memory implementation so they can inspect what would have
 * been sent without any real network call.
 *
 * Both codes are short-lived, single-use, 6-digit numeric codes the user
 * types directly into the app - never a clickable link - see
 * {@link com.mobilemessenger.backend.auth.token.SecureTokenGenerator}.
 */
public interface EmailService {

    void sendVerificationEmail(String toEmail, String username, String verificationCode);

    void sendPasswordResetEmail(String toEmail, String username, String resetCode);
}
