package com.mobilemessenger.backend.email;

import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

/**
 * Production email sender backed by Brevo's transactional email HTTPS API
 * ({@code POST https://api.brevo.com/v3/smtp/email}) rather than SMTP.
 *
 * <p>Added because Railway's current plan cannot open an outbound SMTP
 * connection - a real deployment attempt with {@link SmtpEmailService} failed
 * with "Couldn't connect to host, port: smtp-relay.brevo.com, 587" /
 * {@code ConnectException: Connection timed out}, while plain outbound HTTPS
 * (what this class uses instead) works. Selected the same way as the other
 * two {@link EmailService} implementations, via {@code app.email.provider}.
 *
 * <p>Same message subject/body and the same {@code app.email.from} sender as
 * {@link SmtpEmailService} - only the transport differs. A failed request is
 * deliberately left to propagate to the caller ({@link
 * com.mobilemessenger.backend.auth.EmailVerificationService} already catches
 * and logs any {@link EmailService} failure without failing the surrounding
 * operation - see its Javadoc), exactly like a {@code MailException} from
 * {@link SmtpEmailService} would be.
 */
@Service
@ConditionalOnProperty(name = "app.email.provider", havingValue = "brevo")
public class BrevoEmailService implements EmailService {

    private static final Logger log = LoggerFactory.getLogger(BrevoEmailService.class);
    private static final String BREVO_ENDPOINT = "https://api.brevo.com/v3/smtp/email";

    private final RestClient restClient;
    private final String apiKey;
    private final String fromAddress;

    public BrevoEmailService(
            RestClient.Builder restClientBuilder,
            @Value("${app.brevo.api-key}") String apiKey,
            @Value("${app.email.from}") String fromAddress) {
        this.restClient = restClientBuilder.build();
        this.apiKey = apiKey;
        this.fromAddress = fromAddress;
    }

    @Override
    public void sendVerificationEmail(String toEmail, String username, String verificationCode) {
        send(toEmail, "Verify your Mobile Messenger email", """
                Hi %s,

                Please verify your email address by opening the Mobile Messenger app and entering this verification code:

                %s

                This code expires in 24 hours.

                If you didn't create this account, you can ignore this email.
                """.formatted(username, verificationCode));
        log.info("Verification email sent to {}", maskEmail(toEmail));
    }

    @Override
    public void sendPasswordResetEmail(String toEmail, String username, String resetCode) {
        send(toEmail, "Reset your Mobile Messenger password", """
                Hi %s,

                You requested to reset your Mobile Messenger password.

                Open the Mobile Messenger app and enter this password reset code:

                %s

                This code expires in 1 hour.

                If you didn't request a password reset, you can ignore this email.
                """.formatted(username, resetCode));
        log.info("Password reset email sent to {}", maskEmail(toEmail));
    }

    /**
     * Posts one transactional email to Brevo. Lets any non-2xx response or
     * connection failure propagate as an unchecked exception - the caller
     * already treats a failed send as non-fatal (see class Javadoc), so this
     * class doesn't need its own swallow-and-log; it only logs the mundane
     * fact that a request was attempted (never the code) on success, above.
     */
    private void send(String toEmail, String subject, String textContent) {
        restClient.post()
                .uri(BREVO_ENDPOINT)
                .header("api-key", apiKey)
                .contentType(MediaType.APPLICATION_JSON)
                .body(new BrevoSendRequest(
                        new BrevoAddress(fromAddress), List.of(new BrevoAddress(toEmail)), subject, textContent))
                .retrieve()
                .toBodilessEntity();
    }

    private String maskEmail(String email) {
        int at = email.indexOf('@');
        if (at <= 1) {
            return "***" + email.substring(Math.max(at, 0));
        }
        return email.charAt(0) + "***" + email.substring(at);
    }

    private record BrevoAddress(String email) {
    }

    /** Matches Brevo's {@code /v3/smtp/email} request body shape exactly. */
    private record BrevoSendRequest(BrevoAddress sender, List<BrevoAddress> to, String subject, String textContent) {
    }
}
