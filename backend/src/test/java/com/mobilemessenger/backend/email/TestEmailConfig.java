package com.mobilemessenger.backend.email;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;

/**
 * Replaces whichever {@link EmailService} would otherwise be active
 * (log or smtp) with an in-memory recorder, so integration tests never
 * attempt a real SMTP connection and can assert on what was "sent".
 */
@TestConfiguration
public class TestEmailConfig {

    @Bean
    @Primary
    public RecordingEmailService emailService() {
        return new RecordingEmailService();
    }
}
