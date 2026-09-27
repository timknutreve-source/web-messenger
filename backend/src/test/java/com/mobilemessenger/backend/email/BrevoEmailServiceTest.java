package com.mobilemessenger.backend.email;

import static org.hamcrest.Matchers.containsString;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.content;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.jsonPath;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

/**
 * Pure unit tests for {@link BrevoEmailService}: no Spring context, no
 * database, no real network call - {@link MockRestServiceServer} intercepts
 * the request the same way it would for a plain {@link RestClient}.
 */
class BrevoEmailServiceTest {

    private static final String API_KEY = "test-brevo-api-key";
    private static final String FROM_ADDRESS = "no-reply@example.com";
    private static final String ENDPOINT = "https://api.brevo.com/v3/smtp/email";

    private MockRestServiceServer mockServer;
    private BrevoEmailService service;

    @BeforeEach
    void setUp() {
        RestClient.Builder builder = RestClient.builder();
        mockServer = MockRestServiceServer.bindTo(builder).build();
        service = new BrevoEmailService(builder, API_KEY, FROM_ADDRESS);
    }

    @Test
    void verificationEmailPostsToTheBrevoEndpointWithTheApiKeyHeaderAndCorrectAddresses() {
        mockServer.expect(requestTo(ENDPOINT))
                .andExpect(method(HttpMethod.POST))
                .andExpect(header("api-key", API_KEY))
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.sender.email").value(FROM_ADDRESS))
                .andExpect(jsonPath("$.to[0].email").value("alice@example.com"))
                .andExpect(jsonPath("$.subject").value("Verify your Mobile Messenger email"))
                .andRespond(withSuccess());

        service.sendVerificationEmail("alice@example.com", "alice", "123456");

        mockServer.verify();
    }

    @Test
    void verificationEmailBodyContainsTheVerificationCode() {
        mockServer.expect(requestTo(ENDPOINT))
                .andExpect(jsonPath("$.textContent", containsString("123456")))
                .andRespond(withSuccess());

        service.sendVerificationEmail("alice@example.com", "alice", "123456");

        mockServer.verify();
    }

    @Test
    void passwordResetEmailPostsToTheBrevoEndpointWithTheCorrectSubjectAndAddresses() {
        mockServer.expect(requestTo(ENDPOINT))
                .andExpect(method(HttpMethod.POST))
                .andExpect(header("api-key", API_KEY))
                .andExpect(jsonPath("$.sender.email").value(FROM_ADDRESS))
                .andExpect(jsonPath("$.to[0].email").value("bob@example.com"))
                .andExpect(jsonPath("$.subject").value("Reset your Mobile Messenger password"))
                .andRespond(withSuccess());

        service.sendPasswordResetEmail("bob@example.com", "bob", "654321");

        mockServer.verify();
    }

    @Test
    void passwordResetEmailBodyContainsTheResetCode() {
        mockServer.expect(requestTo(ENDPOINT))
                .andExpect(jsonPath("$.textContent", containsString("654321")))
                .andRespond(withSuccess());

        service.sendPasswordResetEmail("bob@example.com", "bob", "654321");

        mockServer.verify();
    }

    @Test
    void aBrevoHttpErrorPropagatesRatherThanBeingSwallowed() {
        mockServer.expect(requestTo(ENDPOINT)).andRespond(withServerError());

        assertThrows(RestClientException.class,
                () -> service.sendVerificationEmail("alice@example.com", "alice", "123456"));

        mockServer.verify();
    }
}
