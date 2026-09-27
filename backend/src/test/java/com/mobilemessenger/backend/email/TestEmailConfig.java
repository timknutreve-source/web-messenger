package com.mobilemessenger.backend.email;

import java.util.concurrent.Executor;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;

/**
 * Replaces whichever {@link EmailService} would otherwise be active
 * (log, smtp, or brevo) with an in-memory recorder, so integration tests
 * never attempt a real network call and can assert on what was "sent".
 *
 * <p>Also replaces the {@code "email"}-qualified {@link Executor} (see
 * {@link EmailExecutorConfig}) with one that runs its task synchronously,
 * on the calling thread - production dispatches a verification/reset email
 * on a background thread so it never blocks the request (see {@code
 * EmailVerificationService}/{@code PasswordResetService}), but a test
 * asserting on {@link RecordingEmailService#getSentEmails()} right after
 * `mockMvc.perform(...)` returns needs that recording to have already
 * happened - a real async executor would make that assertion flaky.
 */
@TestConfiguration
public class TestEmailConfig {

    @Bean
    @Primary
    public RecordingEmailService emailService() {
        return new RecordingEmailService();
    }

    @Bean
    @Qualifier("email")
    @Primary
    public Executor testEmailExecutor() {
        return Runnable::run;
    }
}
