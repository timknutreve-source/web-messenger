package com.mobilemessenger.backend.email;

import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

/**
 * Test double for {@link EmailService} that records what would have been
 * sent instead of actually sending anything, so tests can inspect generated
 * verification/reset codes without any real network call.
 */
public class RecordingEmailService implements EmailService {

    public record SentEmail(String type, String toEmail, String username, String code) {
    }

    private final List<SentEmail> sentEmails = new CopyOnWriteArrayList<>();

    @Override
    public void sendVerificationEmail(String toEmail, String username, String verificationCode) {
        sentEmails.add(new SentEmail("verification", toEmail, username, verificationCode));
    }

    @Override
    public void sendPasswordResetEmail(String toEmail, String username, String resetCode) {
        sentEmails.add(new SentEmail("reset", toEmail, username, resetCode));
    }

    public List<SentEmail> getSentEmails() {
        return sentEmails;
    }

    public void clear() {
        sentEmails.clear();
    }
}
