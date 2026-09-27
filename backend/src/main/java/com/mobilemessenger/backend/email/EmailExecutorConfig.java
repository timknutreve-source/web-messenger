package com.mobilemessenger.backend.email;

import java.util.concurrent.Executor;
import java.util.concurrent.Executors;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * The {@link Executor} verification/reset emails are dispatched on (see
 * {@link com.mobilemessenger.backend.auth.EmailVerificationService} and
 * {@link com.mobilemessenger.backend.auth.PasswordResetService}), so that
 * sending one - a synchronous HTTP(S) call, see {@link BrevoEmailService}/
 * {@link SmtpEmailService} - never blocks the {@code /register}/{@code
 * /resend-verification}/{@code /forgot-password} HTTP response, or holds
 * open the DB transaction that just persisted the user/token, while it runs.
 *
 * <p>A virtual thread per email is exactly the right shape for this: rare,
 * bursty, I/O-bound work with no meaningful pool-sizing decision to make.
 *
 * <p>Qualified explicitly ({@code "email"}) rather than left as the sole/
 * default {@code Executor} bean, since Spring Boot's own task-execution
 * autoconfiguration may register its own unrelated one - this bean must
 * never be ambiguous with that, and tests (see {@code TestEmailConfig})
 * substitute a synchronous one under the same qualifier so an integration
 * test can still assert on what "would have been sent" deterministically.
 */
@Configuration
public class EmailExecutorConfig {

    @Bean
    @Qualifier("email")
    public Executor emailExecutor() {
        return Executors.newVirtualThreadPerTaskExecutor();
    }
}
