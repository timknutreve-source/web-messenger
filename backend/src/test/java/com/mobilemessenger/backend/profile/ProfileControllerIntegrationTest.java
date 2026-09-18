package com.mobilemessenger.backend.profile;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.test.web.servlet.request.MockMultipartHttpServletRequestBuilder;
import org.springframework.transaction.annotation.Transactional;
import com.mobilemessenger.backend.user.UserRepository;
import java.util.UUID;
import tools.jackson.databind.json.JsonMapper;

/**
 * End-to-end tests for the profile API against a real database and real
 * filesystem storage. Each test runs in its own transaction that is rolled
 * back afterwards, so tests never leak data into one another.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class ProfileControllerIntegrationTest {

    private static final String STRONG_PASSWORD = "Str0ng!Pass";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    private final JsonMapper jsonMapper = JsonMapper.builder().build();

    @Test
    void authenticatedUserCanRetrieveOwnProfile() throws Exception {
        String token = registerAndGetToken("alice", "alice@example.com");

        mockMvc.perform(get("/api/profile").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.username").value("alice"))
                .andExpect(jsonPath("$.email").value("alice@example.com"))
                .andExpect(jsonPath("$.passwordHash").doesNotExist());
    }

    @Test
    void unauthenticatedUserCannotRetrieveProfile() throws Exception {
        mockMvc.perform(get("/api/profile")).andExpect(status().isUnauthorized());
    }

    @Test
    void newUserHasNoAvatarByDefault() throws Exception {
        String token = registerAndGetToken("newbie", "newbie@example.com");

        mockMvc.perform(get("/api/profile").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.avatarFileName", org.hamcrest.Matchers.nullValue()));
    }

    @Test
    void authenticatedUserCanUpdateOwnProfile() throws Exception {
        String token = registerAndGetToken("bob", "bob@example.com");

        mockMvc.perform(updateProfileRequest(token, "bob", "bob@example.com", "I like Flutter"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.username").value("bob"))
                .andExpect(jsonPath("$.aboutMe").value("I like Flutter"));
    }

    @Test
    void savingAnUnchangedUsernameDoesNotConflictWithSelf() throws Exception {
        String token = registerAndGetToken("carol", "carol@example.com");

        mockMvc.perform(updateProfileRequest(token, "carol", "carol@example.com", "still me"))
                .andExpect(status().isOk());
    }

    @Test
    void profileChangesPersist() throws Exception {
        String token = registerAndGetToken("dave", "dave@example.com");

        mockMvc.perform(updateProfileRequest(token, "dave", "dave@example.com", "persisted bio"))
                .andExpect(status().isOk());

        mockMvc.perform(get("/api/profile").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.aboutMe").value("persisted bio"));
    }

    @Test
    void usernameUniquenessIsEnforcedOnUpdate() throws Exception {
        registerAndGetToken("erin", "erin@example.com");
        String token = registerAndGetToken("frank", "frank@example.com");

        mockMvc.perform(updateProfileRequest(token, "ERIN", "frank@example.com", ""))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error").value("Username is already taken"));
    }

    @Test
    void emailUniquenessIsEnforcedOnUpdate() throws Exception {
        registerAndGetToken("grace", "grace@example.com");
        String token = registerAndGetToken("henry", "henry@example.com");

        mockMvc.perform(updateProfileRequest(token, "henry", "grace@example.com", ""))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error").value("Email is already registered"));
    }

    @Test
    void changingEmailResetsEmailVerified() throws Exception {
        String token = registerAndGetToken("iris", "iris@example.com");

        mockMvc.perform(updateProfileRequest(token, "iris", "iris-new@example.com", ""))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.email").value("iris-new@example.com"))
                .andExpect(jsonPath("$.emailVerified").value(false));
    }

    @Test
    void invalidEmailIsRejectedOnUpdate() throws Exception {
        String token = registerAndGetToken("jack", "jack@example.com");

        mockMvc.perform(updateProfileRequest(token, "jack", "not-an-email", ""))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.fieldErrors.email").exists());
    }

    @Test
    void invalidUsernameIsRejectedOnUpdate() throws Exception {
        String token = registerAndGetToken("kate", "kate@example.com");

        mockMvc.perform(updateProfileRequest(token, "a", "kate@example.com", ""))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.fieldErrors.username").exists());
    }

    @Test
    void aboutMeMaxLengthIsEnforced() throws Exception {
        String token = registerAndGetToken("liam", "liam@example.com");
        String tooLong = "a".repeat(501);

        mockMvc.perform(updateProfileRequest(token, "liam", "liam@example.com", tooLong))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.fieldErrors.aboutMe").exists());
    }

    @Test
    void jpegUploadSucceeds() throws Exception {
        String token = registerAndGetToken("mia", "mia@example.com");
        MockMultipartFile file = new MockMultipartFile(
                "file", "avatar.jpg", MediaType.IMAGE_JPEG_VALUE, generateImageBytes("jpg"));

        mockMvc.perform(avatarUpload(token, file))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.avatarFileName", org.hamcrest.Matchers.endsWith(".jpg")));
    }

    @Test
    void pngUploadSucceeds() throws Exception {
        String token = registerAndGetToken("noah", "noah@example.com");
        MockMultipartFile file = new MockMultipartFile(
                "file", "avatar.png", MediaType.IMAGE_PNG_VALUE, generateImageBytes("png"));

        mockMvc.perform(avatarUpload(token, file))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.avatarFileName", org.hamcrest.Matchers.endsWith(".png")));
    }

    @Test
    void fileLargerThan5MbIsRejected() throws Exception {
        String token = registerAndGetToken("olivia", "olivia@example.com");
        byte[] tooLarge = new byte[6 * 1024 * 1024];
        MockMultipartFile file = new MockMultipartFile("file", "big.jpg", MediaType.IMAGE_JPEG_VALUE, tooLarge);

        mockMvc.perform(avatarUpload(token, file))
                .andExpect(status().is(413));
    }

    @Test
    void unsupportedFileTypeIsRejected() throws Exception {
        String token = registerAndGetToken("peter", "peter@example.com");
        MockMultipartFile file = new MockMultipartFile(
                "file", "notes.txt", MediaType.TEXT_PLAIN_VALUE, "not an image".getBytes());

        mockMvc.perform(avatarUpload(token, file))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Only JPEG and PNG images are supported"));
    }

    @Test
    void uploadedAvatarCanBeRetrieved() throws Exception {
        String token = registerAndGetToken("quinn", "quinn@example.com");
        MockMultipartFile file = new MockMultipartFile(
                "file", "avatar.png", MediaType.IMAGE_PNG_VALUE, generateImageBytes("png"));

        MvcResult uploadResult = mockMvc.perform(avatarUpload(token, file))
                .andExpect(status().isOk())
                .andReturn();
        String avatarFileName = jsonMapper.readTree(uploadResult.getResponse().getContentAsString())
                .get("avatarFileName").asString();

        mockMvc.perform(get("/api/profile/avatar/" + avatarFileName).header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers
                        .content().contentType(MediaType.IMAGE_PNG));
    }

    @Test
    void avatarRequiresAuthentication() throws Exception {
        String token = registerAndGetToken("ruth", "ruth@example.com");
        MockMultipartFile file = new MockMultipartFile(
                "file", "avatar.png", MediaType.IMAGE_PNG_VALUE, generateImageBytes("png"));
        MvcResult uploadResult = mockMvc.perform(avatarUpload(token, file))
                .andExpect(status().isOk())
                .andReturn();
        String avatarFileName = jsonMapper.readTree(uploadResult.getResponse().getContentAsString())
                .get("avatarFileName").asString();

        mockMvc.perform(get("/api/profile/avatar/" + avatarFileName))
                .andExpect(status().isUnauthorized());
    }

    private String registerAndGetToken(String username, String email) throws Exception {
        String body = jsonMapper.writeValueAsString(new RegisterPayload(username, email, STRONG_PASSWORD));
        MvcResult result = mockMvc.perform(
                        post("/api/auth/register").contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isCreated())
                .andReturn();
        var node = jsonMapper.readTree(result.getResponse().getContentAsString());
        UUID id = UUID.fromString(node.get("user").get("id").asString());
        userRepository.findById(id).ifPresent(user -> {
            user.setEmailVerified(true);
            userRepository.save(user);
        });
        return node.get("token").asString();
    }

    private MockHttpServletRequestBuilder updateProfileRequest(
            String token, String username, String email, String aboutMe) throws Exception {
        String body = jsonMapper.writeValueAsString(new UpdateProfilePayload(username, email, aboutMe));
        return put("/api/profile")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body);
    }

    private MockMultipartHttpServletRequestBuilder avatarUpload(String token, MockMultipartFile file) {
        return multipart("/api/profile/avatar")
                .file(file)
                .header("Authorization", "Bearer " + token);
    }

    private byte[] generateImageBytes(String format) throws Exception {
        BufferedImage image = new BufferedImage(10, 10, BufferedImage.TYPE_INT_RGB);
        Graphics2D graphics = image.createGraphics();
        graphics.setColor(Color.RED);
        graphics.fillRect(0, 0, 10, 10);
        graphics.dispose();
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageIO.write(image, format, out);
        return out.toByteArray();
    }

    private record RegisterPayload(String username, String email, String password) {
    }

    private record UpdateProfilePayload(String username, String email, String aboutMe) {
    }
}
