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
import com.mobilemessenger.backend.user.UserRepository;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
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

/**
 * Verification is code-based (a 6-digit code emailed to the user, entered
 * in the app) rather than link-based, and {@code POST /api/auth/verify-email}
 * requires the caller's own auth token (a bare code isn't enough to identify
 * whose it is) - see {@link EmailVerificationService}.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Import(TestEmailConfig.class)
@Transactional
class EmailVerificationControllerIntegrationTest {

    private static final String STRONG_PASSWORD = "Str0ng!Pass";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private RecordingEmailService emailService;

    @Autowired
    private EmailVerificationTokenRepository tokenRepository;

    @Autowired
    private UserRepository userRepository;

    private final JsonMapper jsonMapper = JsonMapper.builder().build();

    @BeforeEach
    void clearRecordedEmails() {
        emailService.clear();
    }

    @Test
    void registrationCreatesAndSendsAVerificationCode() throws Exception {
        registerAndGetToken("alice", "alice@example.com");

        List<RecordingEmailService.SentEmail> sent = emailService.getSentEmails();
        assertThat(sent).hasSize(1);
        assertThat(sent.get(0).type()).isEqualTo("verification");
        assertThat(sent.get(0).toEmail()).isEqualTo("alice@example.com");
        assertThat(sent.get(0).code()).matches("\\d{6}");
    }

    @Test
    void anUnverifiedAccountCannotUseTheAppYet() throws Exception {
        String authToken = registerAndGetToken("ivy", "ivy@example.com");

        mockMvc.perform(get("/api/contacts").header("Authorization", "Bearer " + authToken))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error").value("Please verify your email address to continue."));
    }

    @Test
    void verifyEmailSucceedsWithValidCodeAndUnlocksTheApp() throws Exception {
        String authToken = registerAndGetToken("bob", "bob@example.com");
        String code = lastSentCode();

        mockMvc.perform(verifyEmailRequest(authToken, code))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("Your email has been verified."));

        mockMvc.perform(get("/api/auth/me").header("Authorization", "Bearer " + authToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.emailVerified").value(true));

        // Now that the account is verified, a normal endpoint stops being blocked.
        mockMvc.perform(get("/api/contacts").header("Authorization", "Bearer " + authToken))
                .andExpect(status().isOk());
    }

    @Test
    void verifyEmailRequiresAuthentication() throws Exception {
        mockMvc.perform(post("/api/auth/verify-email")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(jsonMapper.writeValueAsString(new VerifyPayload("123456"))))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void verifyEmailFailsWithWrongCode() throws Exception {
        String authToken = registerAndGetToken("carol", "carol@example.com");
        String wrongCode = wrongCode(lastSentCode());

        mockMvc.perform(verifyEmailRequest(authToken, wrongCode))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value(
                        "This code is invalid or has expired. Please request a new one."));
    }

    @Test
    void verifyEmailRejectsAMalformedCode() throws Exception {
        String authToken = registerAndGetToken("mallory", "mallory@example.com");

        mockMvc.perform(verifyEmailRequest(authToken, "12"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.fieldErrors.code").exists());
    }

    @Test
    void verifyEmailFailsWithExpiredCode() throws Exception {
        String authToken = registerAndGetToken("dave", "dave@example.com");
        String code = lastSentCode();

        expireTheOnlyToken("dave@example.com");

        mockMvc.perform(verifyEmailRequest(authToken, code)).andExpect(status().isBadRequest());
    }

    @Test
    void verifyEmailFailsWithAlreadyUsedCode() throws Exception {
        String authToken = registerAndGetToken("erin", "erin@example.com");
        String code = lastSentCode();

        mockMvc.perform(verifyEmailRequest(authToken, code)).andExpect(status().isOk());
        mockMvc.perform(verifyEmailRequest(authToken, code)).andExpect(status().isBadRequest());
    }

    @Test
    void repeatedWrongGuessesLockTheCodeEvenIfTheRealCodeIsTriedAfterward() throws Exception {
        String authToken = registerAndGetToken("frank", "frank@example.com");
        String code = lastSentCode();
        String wrongCode = wrongCode(code);

        for (int i = 0; i < 5; i++) {
            mockMvc.perform(verifyEmailRequest(authToken, wrongCode)).andExpect(status().isBadRequest());
        }

        // 5 wrong attempts already spent - even the correct code is now rejected;
        // the user must request a fresh code instead.
        mockMvc.perform(verifyEmailRequest(authToken, code)).andExpect(status().isBadRequest());
    }

    @Test
    void resendCreatesANewValidCodeAndInvalidatesThePrevious() throws Exception {
        String authToken = registerAndGetToken("grace", "grace@example.com");
        String firstCode = lastSentCode();

        mockMvc.perform(post("/api/auth/resend-verification").header("Authorization", "Bearer " + authToken))
                .andExpect(status().isOk());

        assertThat(emailService.getSentEmails()).hasSize(2);
        String secondCode = lastSentCode();
        assertThat(secondCode).isNotEqualTo(firstCode);

        mockMvc.perform(verifyEmailRequest(authToken, firstCode)).andExpect(status().isBadRequest());
        mockMvc.perform(verifyEmailRequest(authToken, secondCode)).andExpect(status().isOk());
    }

    @Test
    void resendRequiresAuthentication() throws Exception {
        mockMvc.perform(post("/api/auth/resend-verification")).andExpect(status().isUnauthorized());
    }

    @Test
    void resendFailsWhenAlreadyVerified() throws Exception {
        String authToken = registerAndGetToken("henry", "henry@example.com");
        mockMvc.perform(verifyEmailRequest(authToken, lastSentCode())).andExpect(status().isOk());

        mockMvc.perform(post("/api/auth/resend-verification").header("Authorization", "Bearer " + authToken))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Your email is already verified"));
    }

    @Test
    void verifiedEmailIsNotRevertedByUnrelatedProfileUpdates() throws Exception {
        String authToken = registerAndGetToken("iris", "iris@example.com");
        mockMvc.perform(verifyEmailRequest(authToken, lastSentCode())).andExpect(status().isOk());

        mockMvc.perform(updateProfileRequest(authToken, "iris", "iris@example.com", "just my bio"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.emailVerified").value(true));
    }

    @Test
    void changingEmailAfterVerificationResetsVerifiedState() throws Exception {
        String authToken = registerAndGetToken("jack", "jack@example.com");
        mockMvc.perform(verifyEmailRequest(authToken, lastSentCode())).andExpect(status().isOk());

        mockMvc.perform(updateProfileRequest(authToken, "jack", "jack-new@example.com", ""))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.emailVerified").value(false));
    }

    @Test
    void rawVerificationCodeIsNeverStoredInTheDatabase() throws Exception {
        registerAndGetToken("kate", "kate@example.com");
        String rawCode = lastSentCode();

        UUID userId = userRepository.findByEmail("kate@example.com").orElseThrow().getId();
        List<EmailVerificationToken> tokens = tokenRepository.findByUserId(userId);
        assertThat(tokens).hasSize(1);
        assertThat(tokens.get(0).getTokenHash())
                .isNotEqualTo(rawCode)
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

    private MockHttpServletRequestBuilder verifyEmailRequest(String authToken, String code) throws Exception {
        String body = jsonMapper.writeValueAsString(new VerifyPayload(code));
        return post("/api/auth/verify-email")
                .header("Authorization", "Bearer " + authToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body);
    }

    private MockHttpServletRequestBuilder updateProfileRequest(
            String authToken, String username, String email, String aboutMe) throws Exception {
        String body = jsonMapper.writeValueAsString(new UpdateProfilePayload(username, email, aboutMe));
        return put("/api/profile")
                .header("Authorization", "Bearer " + authToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body);
    }

    private String lastSentCode() {
        List<RecordingEmailService.SentEmail> sent = emailService.getSentEmails();
        return sent.get(sent.size() - 1).code();
    }

    private String wrongCode(String realCode) {
        int asNumber = Integer.parseInt(realCode);
        int wrong = (asNumber + 1) % 1_000_000;
        return String.format("%06d", wrong);
    }

    /**
     * Expires the given user's own (most recent) verification code - never
     * {@code findAll().get(0)}, which would grab an arbitrary row out of
     * whichever tokens happen to already exist in the database (e.g. from
     * real accounts), not necessarily the one this test just created.
     */
    private void expireTheOnlyToken(String email) {
        UUID userId = userRepository.findByEmail(email).orElseThrow().getId();
        List<EmailVerificationToken> tokens = tokenRepository.findByUserId(userId);
        EmailVerificationToken token = tokens.get(tokens.size() - 1);
        EmailVerificationToken expired = new EmailVerificationToken(
                token.getUserId(), token.getTokenHash(), Instant.now().minusSeconds(60));
        tokenRepository.delete(token);
        tokenRepository.flush();
        tokenRepository.save(expired);
    }

    private record RegisterPayload(String username, String email, String password) {
    }

    private record VerifyPayload(String code) {
    }

    private record UpdateProfilePayload(String username, String email, String aboutMe) {
    }
}
