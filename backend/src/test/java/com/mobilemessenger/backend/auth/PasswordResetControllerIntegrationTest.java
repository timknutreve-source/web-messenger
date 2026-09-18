package com.mobilemessenger.backend.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.mobilemessenger.backend.auth.token.PasswordResetToken;
import com.mobilemessenger.backend.auth.token.PasswordResetTokenRepository;
import com.mobilemessenger.backend.email.RecordingEmailService;
import com.mobilemessenger.backend.email.TestEmailConfig;
import java.time.Instant;
import java.util.List;
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
 * Password reset is code-based (a 6-digit code emailed to the user, entered
 * in the app alongside the account's email) rather than link-based - see
 * {@link PasswordResetService}.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Import(TestEmailConfig.class)
@Transactional
class PasswordResetControllerIntegrationTest {

    private static final String STRONG_PASSWORD = "Str0ng!Pass";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private RecordingEmailService emailService;

    @Autowired
    private PasswordResetTokenRepository tokenRepository;

    private final JsonMapper jsonMapper = JsonMapper.builder().build();

    @BeforeEach
    void clearRecordedEmails() {
        emailService.clear();
    }

    @Test
    void forgotPasswordReturnsGenericResponseForKnownEmail() throws Exception {
        registerAndGetToken("alice", "alice@example.com");
        emailService.clear(); // registration itself already sent a verification email

        mockMvc.perform(forgotPasswordRequest("alice@example.com"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message")
                        .value("If that email is registered, password reset instructions have been sent."));

        assertThat(emailService.getSentEmails()).hasSize(1);
        assertThat(emailService.getSentEmails().get(0).type()).isEqualTo("reset");
        assertThat(emailService.getSentEmails().get(0).code()).matches("\\d{6}");
    }

    @Test
    void forgotPasswordReturnsIdenticalGenericResponseForUnknownEmail() throws Exception {
        mockMvc.perform(forgotPasswordRequest("nobody-here@example.com"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message")
                        .value("If that email is registered, password reset instructions have been sent."));

        // No account exists, so nothing should have been sent - proves the
        // generic response isn't just "always say ok while secretly failing".
        assertThat(emailService.getSentEmails()).isEmpty();
    }

    @Test
    void validResetCodeWorks() throws Exception {
        registerAndGetToken("bob", "bob@example.com");
        mockMvc.perform(forgotPasswordRequest("bob@example.com")).andExpect(status().isOk());

        mockMvc.perform(resetPasswordRequest("bob@example.com", lastSentCode(), "NewStr0ng!Pass1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("Your password has been reset. You can now log in."));
    }

    @Test
    void resetPasswordFailsWithWrongCode() throws Exception {
        registerAndGetToken("mallory", "mallory@example.com");
        mockMvc.perform(forgotPasswordRequest("mallory@example.com")).andExpect(status().isOk());

        mockMvc.perform(resetPasswordRequest("mallory@example.com", wrongCode(lastSentCode()), "NewStr0ng!Pass1"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value(
                        "This code is invalid or has expired. Please request a new one."));
    }

    @Test
    void resetPasswordFailsForAnUnknownEmailWithTheSameGenericError() throws Exception {
        mockMvc.perform(resetPasswordRequest("nobody-here@example.com", "123456", "NewStr0ng!Pass1"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value(
                        "This code is invalid or has expired. Please request a new one."));
    }

    @Test
    void resetPasswordRejectsAMalformedCode() throws Exception {
        registerAndGetToken("olga", "olga@example.com");
        mockMvc.perform(forgotPasswordRequest("olga@example.com")).andExpect(status().isOk());

        mockMvc.perform(resetPasswordRequest("olga@example.com", "abc", "NewStr0ng!Pass1"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.fieldErrors.code").exists());
    }

    @Test
    void resetPasswordFailsWithExpiredCode() throws Exception {
        registerAndGetToken("carol", "carol@example.com");
        mockMvc.perform(forgotPasswordRequest("carol@example.com")).andExpect(status().isOk());
        String code = lastSentCode();

        expireTheOnlyToken();

        mockMvc.perform(resetPasswordRequest("carol@example.com", code, "NewStr0ng!Pass1"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void usedResetCodeCannotBeReused() throws Exception {
        registerAndGetToken("dave", "dave@example.com");
        mockMvc.perform(forgotPasswordRequest("dave@example.com")).andExpect(status().isOk());
        String code = lastSentCode();

        mockMvc.perform(resetPasswordRequest("dave@example.com", code, "NewStr0ng!Pass1"))
                .andExpect(status().isOk());
        mockMvc.perform(resetPasswordRequest("dave@example.com", code, "AnotherStr0ng!Pass2"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void repeatedWrongGuessesLockTheCodeEvenIfTheRealCodeIsTriedAfterward() throws Exception {
        registerAndGetToken("frank", "frank@example.com");
        mockMvc.perform(forgotPasswordRequest("frank@example.com")).andExpect(status().isOk());
        String code = lastSentCode();
        String wrong = wrongCode(code);

        for (int i = 0; i < 5; i++) {
            mockMvc.perform(resetPasswordRequest("frank@example.com", wrong, "NewStr0ng!Pass1"))
                    .andExpect(status().isBadRequest());
        }

        mockMvc.perform(resetPasswordRequest("frank@example.com", code, "NewStr0ng!Pass1"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void requestingANewResetInvalidatesThePreviousCode() throws Exception {
        registerAndGetToken("erin", "erin@example.com");

        mockMvc.perform(forgotPasswordRequest("erin@example.com")).andExpect(status().isOk());
        String firstCode = lastSentCode();

        mockMvc.perform(forgotPasswordRequest("erin@example.com")).andExpect(status().isOk());
        String secondCode = lastSentCode();
        assertThat(secondCode).isNotEqualTo(firstCode);

        mockMvc.perform(resetPasswordRequest("erin@example.com", firstCode, "NewStr0ng!Pass1"))
                .andExpect(status().isBadRequest());
        mockMvc.perform(resetPasswordRequest("erin@example.com", secondCode, "NewStr0ng!Pass1"))
                .andExpect(status().isOk());
    }

    @Test
    void weakPasswordIsRejected() throws Exception {
        registerAndGetToken("frank2", "frank2@example.com");
        mockMvc.perform(forgotPasswordRequest("frank2@example.com")).andExpect(status().isOk());

        mockMvc.perform(resetPasswordRequest("frank2@example.com", lastSentCode(), "weak"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.fieldErrors.newPassword").exists());
    }

    @Test
    void passwordIsActuallyChangedAndOldPasswordStopsWorking() throws Exception {
        registerAndGetToken("grace", "grace@example.com");
        mockMvc.perform(forgotPasswordRequest("grace@example.com")).andExpect(status().isOk());
        mockMvc.perform(resetPasswordRequest("grace@example.com", lastSentCode(), "NewStr0ng!Pass1"))
                .andExpect(status().isOk());

        mockMvc.perform(loginRequest("grace", STRONG_PASSWORD)).andExpect(status().isUnauthorized());
        mockMvc.perform(loginRequest("grace", "NewStr0ng!Pass1")).andExpect(status().isOk());
    }

    @Test
    void resetPasswordResponseNeverIncludesThePassword() throws Exception {
        registerAndGetToken("henry", "henry@example.com");
        mockMvc.perform(forgotPasswordRequest("henry@example.com")).andExpect(status().isOk());

        mockMvc.perform(resetPasswordRequest("henry@example.com", lastSentCode(), "NewStr0ng!Pass1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.newPassword").doesNotExist())
                .andExpect(jsonPath("$.password").doesNotExist())
                .andExpect(jsonPath("$.passwordHash").doesNotExist());
    }

    @Test
    void rawResetCodeIsNeverStoredInTheDatabase() throws Exception {
        registerAndGetToken("iris", "iris@example.com");
        mockMvc.perform(forgotPasswordRequest("iris@example.com")).andExpect(status().isOk());
        String rawCode = lastSentCode();

        List<PasswordResetToken> tokens = tokenRepository.findAll();
        assertThat(tokens).hasSize(1);
        assertThat(tokens.get(0).getTokenHash())
                .isNotEqualTo(rawCode)
                .hasSize(64);
    }

    private String registerAndGetToken(String username, String email) throws Exception {
        String body = jsonMapper.writeValueAsString(new RegisterPayload(username, email, STRONG_PASSWORD));
        MvcResult result = mockMvc.perform(
                        post("/api/auth/register").contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isCreated())
                .andReturn();
        return jsonMapper.readTree(result.getResponse().getContentAsString()).get("token").asString();
    }

    private MockHttpServletRequestBuilder forgotPasswordRequest(String email) throws Exception {
        String body = jsonMapper.writeValueAsString(new ForgotPasswordPayload(email));
        return post("/api/auth/forgot-password").contentType(MediaType.APPLICATION_JSON).content(body);
    }

    private MockHttpServletRequestBuilder resetPasswordRequest(String email, String code, String newPassword)
            throws Exception {
        String body = jsonMapper.writeValueAsString(new ResetPasswordPayload(email, code, newPassword));
        return post("/api/auth/reset-password").contentType(MediaType.APPLICATION_JSON).content(body);
    }

    private MockHttpServletRequestBuilder loginRequest(String usernameOrEmail, String password) throws Exception {
        String body = jsonMapper.writeValueAsString(new LoginPayload(usernameOrEmail, password));
        return post("/api/auth/login").contentType(MediaType.APPLICATION_JSON).content(body);
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

    private void expireTheOnlyToken() {
        PasswordResetToken token = tokenRepository.findAll().get(0);
        PasswordResetToken expired = new PasswordResetToken(
                token.getUserId(), token.getTokenHash(), Instant.now().minusSeconds(60));
        tokenRepository.delete(token);
        tokenRepository.flush();
        tokenRepository.save(expired);
    }

    private record RegisterPayload(String username, String email, String password) {
    }

    private record ForgotPasswordPayload(String email) {
    }

    private record ResetPasswordPayload(String email, String code, String newPassword) {
    }

    private record LoginPayload(String usernameOrEmail, String password) {
    }
}
