package com.mobilemessenger.backend.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.mobilemessenger.backend.auth.token.EmailVerificationToken;
import com.mobilemessenger.backend.auth.token.EmailVerificationTokenRepository;
import com.mobilemessenger.backend.email.RecordingEmailService;
import com.mobilemessenger.backend.email.TestEmailConfig;
import java.time.Instant;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.json.JsonMapper;

@SpringBootTest
@AutoConfigureMockMvc
@Import(TestEmailConfig.class)
@Transactional
class EmailVerificationControllerIntegrationTest {

    private static final String STRONG_PASSWORD = "Str0ng!Pass";
    private static final Pattern TOKEN_PATTERN = Pattern.compile("token=([^&\\s]+)");

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private RecordingEmailService emailService;

    @Autowired
    private EmailVerificationTokenRepository tokenRepository;

    private final JsonMapper jsonMapper = JsonMapper.builder().build();

    @BeforeEach
    void clearRecordedEmails() {
        emailService.clear();
    }

    @Test
    void registrationCreatesAndSendsAVerificationToken() throws Exception {
        registerAndGetToken("alice", "alice@example.com");

        List<RecordingEmailService.SentEmail> sent = emailService.getSentEmails();
        assertThat(sent).hasSize(1);
        assertThat(sent.get(0).type()).isEqualTo("verification");
        assertThat(sent.get(0).toEmail()).isEqualTo("alice@example.com");
        assertThat(extractToken(sent.get(0).link())).isNotBlank();
    }

    @Test
    void verifyEmailSucceedsWithValidToken() throws Exception {
        String authToken = registerAndGetToken("bob", "bob@example.com");
        String verifyToken = extractToken(lastSentLink());

        mockMvc.perform(verifyEmailRequest(verifyToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("Your email has been verified."));

        mockMvc.perform(get("/api/auth/me").header("Authorization", "Bearer " + authToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.emailVerified").value(true));
    }

    @Test
    void verifyEmailFailsWithInvalidToken() throws Exception {
        mockMvc.perform(verifyEmailRequest("not-a-real-token"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value(
                        "This link is invalid or has expired. Please request a new one."));
    }

    @Test
    void verifyEmailFailsWithExpiredToken() throws Exception {
        registerAndGetToken("carol", "carol@example.com");
        String verifyToken = extractToken(lastSentLink());

        expireTheOnlyToken();

        mockMvc.perform(verifyEmailRequest(verifyToken))
                .andExpect(status().isBadRequest());
    }

    @Test
    void verifyEmailFailsWithAlreadyUsedToken() throws Exception {
        registerAndGetToken("dave", "dave@example.com");
        String verifyToken = extractToken(lastSentLink());

        mockMvc.perform(verifyEmailRequest(verifyToken)).andExpect(status().isOk());
        mockMvc.perform(verifyEmailRequest(verifyToken)).andExpect(status().isBadRequest());
    }

    @Test
    void resendCreatesANewValidTokenAndInvalidatesThePrevious() throws Exception {
        String authToken = registerAndGetToken("erin", "erin@example.com");
        String firstToken = extractToken(lastSentLink());

        mockMvc.perform(post("/api/auth/resend-verification").header("Authorization", "Bearer " + authToken))
                .andExpect(status().isOk());

        assertThat(emailService.getSentEmails()).hasSize(2);
        String secondToken = extractToken(lastSentLink());
        assertThat(secondToken).isNotEqualTo(firstToken);

        mockMvc.perform(verifyEmailRequest(firstToken)).andExpect(status().isBadRequest());
        mockMvc.perform(verifyEmailRequest(secondToken)).andExpect(status().isOk());
    }

    @Test
    void resendRequiresAuthentication() throws Exception {
        mockMvc.perform(post("/api/auth/resend-verification")).andExpect(status().isUnauthorized());
    }

    @Test
    void resendFailsWhenAlreadyVerified() throws Exception {
        String authToken = registerAndGetToken("frank", "frank@example.com");
        mockMvc.perform(verifyEmailRequest(extractToken(lastSentLink()))).andExpect(status().isOk());

        mockMvc.perform(post("/api/auth/resend-verification").header("Authorization", "Bearer " + authToken))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Your email is already verified"));
    }

    @Test
    void verifiedEmailIsNotRevertedByUnrelatedProfileUpdates() throws Exception {
        String authToken = registerAndGetToken("grace", "grace@example.com");
        mockMvc.perform(verifyEmailRequest(extractToken(lastSentLink()))).andExpect(status().isOk());

        mockMvc.perform(updateProfileRequest(authToken, "grace", "grace@example.com", "just my bio"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.emailVerified").value(true));
    }

    @Test
    void changingEmailAfterVerificationResetsVerifiedState() throws Exception {
        String authToken = registerAndGetToken("henry", "henry@example.com");
        mockMvc.perform(verifyEmailRequest(extractToken(lastSentLink()))).andExpect(status().isOk());

        mockMvc.perform(updateProfileRequest(authToken, "henry", "henry-new@example.com", ""))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.emailVerified").value(false));
    }

    @Test
    void rawVerificationTokenIsNeverStoredInTheDatabase() throws Exception {
        registerAndGetToken("iris", "iris@example.com");
        String rawToken = extractToken(lastSentLink());

        List<EmailVerificationToken> tokens = tokenRepository.findAll();
        assertThat(tokens).hasSize(1);
        assertThat(tokens.get(0).getTokenHash())
                .isNotEqualTo(rawToken)
                .hasSize(64); // SHA-256 hex
    }

    private String registerAndGetToken(String username, String email) throws Exception {
        String body = jsonMapper.writeValueAsString(new RegisterPayload(username, email, STRONG_PASSWORD));
        MvcResult result = mockMvc.perform(
                        post("/api/auth/register").contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isCreated())
                .andReturn();
        return jsonMapper.readTree(result.getResponse().getContentAsString()).get("token").asString();
    }

    private MockHttpServletRequestBuilder verifyEmailRequest(String token) throws Exception {
        String body = jsonMapper.writeValueAsString(new VerifyPayload(token));
        return post("/api/auth/verify-email").contentType(MediaType.APPLICATION_JSON).content(body);
    }

    private MockHttpServletRequestBuilder updateProfileRequest(
            String authToken, String username, String email, String aboutMe) throws Exception {
        String body = jsonMapper.writeValueAsString(new UpdateProfilePayload(username, email, aboutMe));
        return put("/api/profile")
                .header("Authorization", "Bearer " + authToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body);
    }

    private String lastSentLink() {
        List<RecordingEmailService.SentEmail> sent = emailService.getSentEmails();
        return sent.get(sent.size() - 1).link();
    }

    private String extractToken(String link) {
        Matcher matcher = TOKEN_PATTERN.matcher(link);
        if (!matcher.find()) {
            throw new IllegalStateException("No token found in link: " + link);
        }
        return matcher.group(1);
    }

    private void expireTheOnlyToken() {
        EmailVerificationToken token = tokenRepository.findAll().get(0);
        EmailVerificationToken expired = new EmailVerificationToken(
                token.getUserId(), token.getTokenHash(), Instant.now().minusSeconds(60));
        tokenRepository.delete(token);
        tokenRepository.flush();
        tokenRepository.save(expired);
    }

    private record RegisterPayload(String username, String email, String password) {
    }

    private record VerifyPayload(String token) {
    }

    private record UpdateProfilePayload(String username, String email, String aboutMe) {
    }
}
