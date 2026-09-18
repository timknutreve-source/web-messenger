package com.mobilemessenger.backend.email;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Service;

/**
 * Production email sender backed by SMTP (via Spring's {@link JavaMailSender},
 * configured through the standard {@code spring.mail.*} properties - see
 * application.properties / README for the environment variables).
 *
 * Deliberately never logs the verification/reset code itself, only that a
 * message was sent and to which (masked) address, so a live code can never
 * leak into application logs.
 */
@Service
@ConditionalOnProperty(name = "app.email.provider", havingValue = "smtp")
public class SmtpEmailService implements EmailService {

    private static final Logger log = LoggerFactory.getLogger(SmtpEmailService.class);

    private final JavaMailSender mailSender;
    private final String fromAddress;

    public SmtpEmailService(JavaMailSender mailSender, @Value("${app.email.from}") String fromAddress) {
        this.mailSender = mailSender;
        this.fromAddress = fromAddress;
    }

    @Override
    public void sendVerificationEmail(String toEmail, String username, String verificationCode) {
        SimpleMailMessage message = new SimpleMailMessage();
        message.setFrom(fromAddress);
        message.setTo(toEmail);
        message.setSubject("Verify your Mobile Messenger email");
        message.setText("""
                Hi %s,

                Please verify your email address by opening the Mobile Messenger app and entering this verification code:

                %s

                This code expires in 24 hours.

                If you didn't create this account, you can ignore this email.
                """.formatted(username, verificationCode));
        mailSender.send(message);
        log.info("Verification email sent to {}", maskEmail(toEmail));
    }

    @Override
    public void sendPasswordResetEmail(String toEmail, String username, String resetCode) {
        SimpleMailMessage message = new SimpleMailMessage();
        message.setFrom(fromAddress);
        message.setTo(toEmail);
        message.setSubject("Reset your Mobile Messenger password");
        message.setText("""
                Hi %s,

                You requested to reset your Mobile Messenger password.

                Open the Mobile Messenger app and enter this password reset code:

                %s

                This code expires in 1 hour.

                If you didn't request a password reset, you can ignore this email.
                """.formatted(username, resetCode));
        mailSender.send(message);
        log.info("Password reset email sent to {}", maskEmail(toEmail));
    }

    private String maskEmail(String email) {
        int at = email.indexOf('@');
        if (at <= 1) {
            return "***" + email.substring(Math.max(at, 0));
        }
        return email.charAt(0) + "***" + email.substring(at);
    }
}
