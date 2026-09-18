package com.mobilemessenger.backend.security.encryption;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.UUID;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.transaction.annotation.Transactional;
import com.mobilemessenger.backend.user.UserRepository;
import tools.jackson.databind.json.JsonMapper;

/**
 * Proves the core Phase 9 requirement for media: uploaded image/video bytes
 * are encrypted on disk (not just under an encrypted-looking filename), a
 * full download decrypts back to the exact original bytes, and HTTP range
 * requests (video seeking) still return exactly the requested byte range,
 * fully decrypted, without ever exposing the encrypted-at-rest layout to
 * the client.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class AttachmentEncryptionIntegrationTest {

    private static final String STRONG_PASSWORD = "Str0ng!Pass";

    @Autowired
    private MockMvc mockMvc;

    @Value("${storage.root-dir}")
    private String storageRootDir;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private jakarta.persistence.EntityManager entityManager;

    @Autowired
    private UserRepository userRepository;

    private final JsonMapper jsonMapper = JsonMapper.builder().build();

    @Test
    void uploadedImageBytesAreEncryptedOnDisk() throws Exception {
        RegisteredUser alice = register("alice_enc_img", "alice.enc.img@example.com");
        RegisteredUser bob = register("bob_enc_img", "bob.enc.img@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        byte[] originalBytes = jpegBytes(200, 150);
        MockMultipartFile file = new MockMultipartFile("file", "pic.jpg", "image/jpeg", originalBytes);
        MvcResult uploadResult = mockMvc.perform(multipart("/api/chats/" + chatId + "/attachments")
                        .file(file)
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isCreated())
                .andReturn();
        UUID attachmentId = UUID.fromString(
                jsonMapper.readTree(uploadResult.getResponse().getContentAsString()).get("id").asString());
        entityManager.flush();

        byte[] onDiskBytes = readStoredFile("chat-attachments", storageKeyOf(attachmentId));

        // The plaintext JPEG magic bytes/content must not appear anywhere in
        // the stored file - this is the core "not just an encrypted filename"
        // requirement.
        assertFalse(containsSubsequence(onDiskBytes, originalBytes), "on-disk file contains the plaintext image bytes");
        assertNotEquals(originalBytes.length, onDiskBytes.length, "on-disk file should carry encryption overhead");

        // But downloading it returns exactly the original bytes.
        MvcResult downloadResult = mockMvc.perform(
                        get("/api/attachments/" + attachmentId).header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isOk())
                .andExpect(header().string("Content-Type", "image/jpeg"))
                .andReturn();
        assertArrayEquals(originalBytes, downloadResult.getResponse().getContentAsByteArray());
    }

    @Test
    void rangeRequestReturnsExactRequestedSliceOfTheDecryptedVideo() throws Exception {
        RegisteredUser alice = register("alice_enc_vid", "alice.enc.vid@example.com");
        RegisteredUser bob = register("bob_enc_vid", "bob.enc.vid@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        byte[] originalBytes = fakeMp4Bytes(3_000_000); // spans multiple 1 MiB chunks
        MockMultipartFile file = new MockMultipartFile("file", "clip.mp4", "video/mp4", originalBytes);
        MvcResult uploadResult = mockMvc.perform(multipart("/api/chats/" + chatId + "/attachments")
                        .file(file)
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isCreated())
                .andReturn();
        UUID attachmentId = UUID.fromString(
                jsonMapper.readTree(uploadResult.getResponse().getContentAsString()).get("id").asString());
        entityManager.flush();

        byte[] onDiskBytes = readStoredFile("chat-attachments", storageKeyOf(attachmentId));
        assertFalse(containsSubsequence(onDiskBytes, originalBytes), "on-disk file contains the plaintext video bytes");

        // A range spanning a chunk boundary (default chunk size is 1 MiB).
        int start = 1_048_576 - 100;
        int end = 1_048_576 + 100;
        MvcResult rangeResult = mockMvc.perform(get("/api/attachments/" + attachmentId)
                        .header("Authorization", "Bearer " + alice.token)
                        .header(HttpHeaders.RANGE, "bytes=" + start + "-" + end))
                .andExpect(status().isPartialContent())
                .andExpect(header().string(HttpHeaders.CONTENT_RANGE, "bytes " + start + "-" + end + "/" + originalBytes.length))
                .andReturn();

        byte[] expectedSlice = Arrays.copyOfRange(originalBytes, start, end + 1);
        assertArrayEquals(expectedSlice, rangeResult.getResponse().getContentAsByteArray());
    }

    @Test
    void thumbnailBytesAreEncryptedOnDiskAndDecryptCorrectly() throws Exception {
        RegisteredUser alice = register("alice_enc_thumb", "alice.enc.thumb@example.com");
        RegisteredUser bob = register("bob_enc_thumb", "bob.enc.thumb@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        MockMultipartFile file = new MockMultipartFile("file", "big.jpg", "image/jpeg", jpegBytes(1200, 900));
        MvcResult uploadResult = mockMvc.perform(multipart("/api/chats/" + chatId + "/attachments")
                        .file(file)
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isCreated())
                .andReturn();
        var node = jsonMapper.readTree(uploadResult.getResponse().getContentAsString());
        UUID attachmentId = UUID.fromString(node.get("id").asString());
        String thumbnailUrl = node.get("thumbnailUrl").asString();
        entityManager.flush();

        String thumbnailStorageKey = jdbcTemplate.queryForObject(
                "SELECT thumbnail_storage_key FROM message_attachments WHERE id = ?", String.class, attachmentId);
        byte[] onDiskThumbnail = readStoredFile("chat-attachment-thumbnails", thumbnailStorageKey);

        MvcResult thumbnailResult = mockMvc.perform(get(thumbnailUrl).header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isOk())
                .andReturn();
        byte[] decryptedThumbnail = thumbnailResult.getResponse().getContentAsByteArray();

        // The plaintext thumbnail JPEG bytes must not appear as-is on disk,
        // but the API must still return a valid, matching JPEG.
        assertFalse(containsSubsequence(onDiskThumbnail, decryptedThumbnail));
        assertTrue(decryptedThumbnail.length > 0);
        // A real JPEG magic number.
        assertTrue((decryptedThumbnail[0] & 0xFF) == 0xFF && (decryptedThumbnail[1] & 0xFF) == 0xD8);
    }

    // ---- helpers ----

    private String storageKeyOf(UUID attachmentId) {
        return jdbcTemplate.queryForObject(
                "SELECT storage_key FROM message_attachments WHERE id = ?", String.class, attachmentId);
    }

    private byte[] readStoredFile(String category, String storedFileName) throws Exception {
        return Files.readAllBytes(Path.of(storageRootDir).resolve(category).resolve(storedFileName));
    }

    private static boolean containsSubsequence(byte[] haystack, byte[] needle) {
        if (needle.length == 0 || needle.length > haystack.length) {
            return needle.length == 0;
        }
        outer:
        for (int i = 0; i <= haystack.length - needle.length; i++) {
            for (int j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) {
                    continue outer;
                }
            }
            return true;
        }
        return false;
    }

    private UUID becomeContactsAndGetChatId(RegisteredUser sender, RegisteredUser recipient) throws Exception {
        UUID invitationId = sendInvitationAndGetId(sender.token, recipient.id);
        mockMvc.perform(post("/api/contacts/invitations/" + invitationId + "/accept")
                        .header("Authorization", "Bearer " + recipient.token))
                .andExpect(status().isOk());

        MvcResult chatsResult = mockMvc.perform(get("/api/chats").header("Authorization", "Bearer " + sender.token))
                .andExpect(status().isOk())
                .andReturn();
        var node = jsonMapper.readTree(chatsResult.getResponse().getContentAsString());
        return UUID.fromString(node.get(0).get("id").asString());
    }

    private UUID sendInvitationAndGetId(String senderToken, UUID recipientId) throws Exception {
        String body = jsonMapper.writeValueAsString(new SendInvitationPayload(recipientId));
        MvcResult result = mockMvc.perform(post("/api/contacts/invitations")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body)
                        .header("Authorization", "Bearer " + senderToken))
                .andExpect(status().isCreated())
                .andReturn();
        return UUID.fromString(
                jsonMapper.readTree(result.getResponse().getContentAsString()).get("id").asString());
    }

    private RegisteredUser register(String username, String email) throws Exception {
        String body = jsonMapper.writeValueAsString(new RegisterPayload(username, email, STRONG_PASSWORD));
        MvcResult result = mockMvc.perform(
                        post("/api/auth/register").contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isCreated())
                .andReturn();
        var node = jsonMapper.readTree(result.getResponse().getContentAsString());
        String token = node.get("token").asString();
        UUID id = UUID.fromString(node.get("user").get("id").asString());
        userRepository.findById(id).ifPresent(user -> {
            user.setEmailVerified(true);
            userRepository.save(user);
        });
        return new RegisteredUser(id, token);
    }

    private static byte[] jpegBytes(int width, int height) throws Exception {
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        Graphics2D graphics = image.createGraphics();
        graphics.setColor(Color.BLUE);
        graphics.fillRect(0, 0, width, height);
        graphics.dispose();
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageIO.write(image, "jpg", out);
        return out.toByteArray();
    }

    /** Enough of an ISO-base-media-file "ftyp" box for AttachmentValidator to recognize it as MP4, padded to a given size. */
    private static byte[] fakeMp4Bytes(int totalSize) {
        byte[] content = new byte[Math.max(totalSize, 16)];
        byte[] header = {0, 0, 0, 0x18, 'f', 't', 'y', 'p', 'i', 's', 'o', 'm', 0, 0, 0, 0};
        System.arraycopy(header, 0, content, 0, header.length);
        // Fill the rest with non-repeating bytes so a byte-for-byte range
        // comparison is meaningful (not just all zeros).
        for (int i = header.length; i < content.length; i++) {
            content[i] = (byte) (i % 251);
        }
        return content;
    }

    private record RegisteredUser(UUID id, String token) {
    }

    private record RegisterPayload(String username, String email, String password) {
    }

    private record SendInvitationPayload(UUID recipientId) {
    }
}
