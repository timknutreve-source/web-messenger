package com.mobilemessenger.backend.email;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

/**
 * Development/local-testing email "sender": instead of delivering anything,
 * it logs the generated code at INFO level so a developer (or reviewer
 * without SMTP credentials) can copy it straight out of the console.
 *
 * This is the default provider ({@code app.email.provider} unset or
 * {@code log}) so the app never silently tries to reach a real mail server
 * without one being explicitly configured. It must never be selected in a
 * real deployment - {@link SmtpEmailService} does not log the code, since
 * doing so in production would leak live verification/reset codes into logs.
 */
@Service
@ConditionalOnProperty(name = "app.email.provider", havingValue = "log", matchIfMissing = true)
public class LoggingEmailService implements EmailService {

    private static final Logger log = LoggerFactory.getLogger(LoggingEmailService.class);

    @Override
    public void sendVerificationEmail(String toEmail, String username, String verificationCode) {
        log.info(
                "[DEV EMAIL - not actually sent] Verification code for '{}' <{}>: {}",
                username, toEmail, verificationCode);
    }

    @Override
    public void sendPasswordResetEmail(String toEmail, String username, String resetCode) {
        log.info(
                "[DEV EMAIL - not actually sent] Password reset code for '{}' <{}>: {}",
                username, toEmail, resetCode);
    }
}
