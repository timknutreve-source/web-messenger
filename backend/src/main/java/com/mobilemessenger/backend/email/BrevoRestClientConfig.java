package com.mobilemessenger.backend.email;

import java.time.Duration;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

/**
 * The {@code RestClient.Builder} {@link BrevoEmailService} uses, pre-bound to
 * a request factory with an explicit connect/read timeout.
 *
 * <p>Kept as its own bean (rather than configured inline in {@link
 * BrevoEmailService}'s constructor) for one reason: a unit test that binds
 * {@code MockRestServiceServer} to a plain {@code RestClient.builder()} needs
 * that binding to survive untouched - if {@link BrevoEmailService} itself
 * called {@code .requestFactory(...)} on whatever builder it was handed, it
 * would silently replace the mock's factory with a real one, and the test
 * would (as happened during development of this change) make an actual
 * network call instead of hitting the mock. Qualifying this builder ({@code
 * "brevo"}) keeps it unambiguous from any other {@code RestClient.Builder}
 * Spring Boot's own autoconfiguration might also register.
 */
@Configuration
public class BrevoRestClientConfig {

    /**
     * Comfortably under the Flutter client's own ~5s request timeout
     * (`AppConfig.connectTimeout`/`sendTimeout`/`receiveTimeout`), so the
     * backend always answers before the client would otherwise give up -
     * see {@link BrevoEmailService}'s Javadoc for the production incident
     * this fixes.
     */
    private static final Duration TIMEOUT = Duration.ofSeconds(4);

    @Bean
    @Qualifier("brevo")
    public RestClient.Builder brevoRestClientBuilder() {
        SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(TIMEOUT);
        requestFactory.setReadTimeout(TIMEOUT);
        return RestClient.builder().requestFactory(requestFactory);
    }
}
