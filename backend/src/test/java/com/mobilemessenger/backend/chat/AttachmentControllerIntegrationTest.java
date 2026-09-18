package com.mobilemessenger.backend.chat;

import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.notNullValue;
import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.UUID;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.transaction.annotation.Transactional;
import com.mobilemessenger.backend.user.UserRepository;
import tools.jackson.databind.json.JsonMapper;

/**
 * End-to-end tests for Phase 8 image/video attachments: upload validation,
 * authorization, attaching to messages, download/thumbnail access, and
 * deleted-message media inaccessibility, against a real database.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class AttachmentControllerIntegrationTest {

    private static final String STRONG_PASSWORD = "Str0ng!Pass";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ConversationRepository conversationRepository;

    @Autowired
    private MessageAttachmentRepository attachmentRepository;

    @Autowired
    private UserRepository userRepository;

    private final JsonMapper jsonMapper = JsonMapper.builder().build();

    // ---- upload authorization ----

    @Test
    void participantCanUploadAnImage() throws Exception {
        RegisteredUser alice = register("alice_att_upload", "alice.att.upload@example.com");
        RegisteredUser bob = register("bob_att_upload", "bob.att.upload@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        uploadImage(alice.token, chatId, 200, 150)
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id", notNullValue()))
                .andExpect(jsonPath("$.type").value("IMAGE"))
                .andExpect(jsonPath("$.mimeType").value("image/jpeg"))
                .andExpect(jsonPath("$.width").value(200))
                .andExpect(jsonPath("$.height").value(150))
                .andExpect(jsonPath("$.url").value(org.hamcrest.Matchers.startsWith("/api/attachments/")));
    }

    @Test
    void nonParticipantCannotUpload() throws Exception {
        RegisteredUser alice = register("alice_att_noup", "alice.att.noup@example.com");
        RegisteredUser bob = register("bob_att_noup", "bob.att.noup@example.com");
        RegisteredUser carol = register("carol_att_noup", "carol.att.noup@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        uploadImage(carol.token, chatId, 100, 100).andExpect(status().isNotFound());
    }

    @Test
    void uploadRequiresAuthentication() throws Exception {
        mockMvc.perform(multipart("/api/chats/" + UUID.randomUUID() + "/attachments")
                        .file(new MockMultipartFile("file", "x.jpg", "image/jpeg", jpegBytes(10, 10))))
                .andExpect(status().isUnauthorized());
    }

    // ---- validation ----

    @Test
    void validPngImageIsAccepted() throws Exception {
        RegisteredUser alice = register("alice_att_png", "alice.att.png@example.com");
        RegisteredUser bob = register("bob_att_png", "bob.att.png@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        MockMultipartFile file = new MockMultipartFile("file", "pic.png", "image/png", pngBytes(64, 48));
        mockMvc.perform(multipart("/api/chats/" + chatId + "/attachments")
                        .file(file)
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.type").value("IMAGE"))
                .andExpect(jsonPath("$.mimeType").value("image/png"));
    }

    @Test
    void validVideoIsAccepted() throws Exception {
        RegisteredUser alice = register("alice_att_video", "alice.att.video@example.com");
        RegisteredUser bob = register("bob_att_video", "bob.att.video@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        MockMultipartFile file = new MockMultipartFile("file", "clip.mp4", "video/mp4", fakeMp4Bytes(4096));
        mockMvc.perform(multipart("/api/chats/" + chatId + "/attachments")
                        .file(file)
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.type").value("VIDEO"))
                .andExpect(jsonPath("$.mimeType").value("video/mp4"));
    }

    @Test
    void validAudioMessageIsAcceptedWithDuration() throws Exception {
        RegisteredUser alice = register("alice_att_audio", "alice.att.audio@example.com");
        RegisteredUser bob = register("bob_att_audio", "bob.att.audio@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        MockMultipartFile file = new MockMultipartFile("file", "voice.wav", "audio/wav", fakeWavBytes(4096));
        mockMvc.perform(multipart("/api/chats/" + chatId + "/attachments")
                        .file(file)
                        .param("durationSeconds", "7")
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.type").value("AUDIO"))
                .andExpect(jsonPath("$.mimeType").value("audio/wav"))
                .andExpect(jsonPath("$.durationSeconds").value(7));
    }

    @Test
    void audioMessageWithoutDurationIsStillAccepted() throws Exception {
        RegisteredUser alice = register("alice_att_audio_nodur", "alice.att.audio.nodur@example.com");
        RegisteredUser bob = register("bob_att_audio_nodur", "bob.att.audio.nodur@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        MockMultipartFile file = new MockMultipartFile("file", "voice.wav", "audio/wav", fakeWavBytes(1024));
        mockMvc.perform(multipart("/api/chats/" + chatId + "/attachments")
                        .file(file)
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.type").value("AUDIO"))
                .andExpect(jsonPath("$.durationSeconds").doesNotExist());
    }

    @Test
    void oversizedAudioMessageIsRejected() throws Exception {
        RegisteredUser alice = register("alice_att_audio_big", "alice.att.audio.big@example.com");
        RegisteredUser bob = register("bob_att_audio_big", "bob.att.audio.big@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        // Default audio limit is 15MB.
        MockMultipartFile file =
                new MockMultipartFile("file", "voice.wav", "audio/wav", fakeWavBytes(16 * 1024 * 1024));
        mockMvc.perform(multipart("/api/chats/" + chatId + "/attachments")
                        .file(file)
                        .param("durationSeconds", "600")
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isPayloadTooLarge());
    }

    @Test
    void audioMessageCanBeSentAndDownloadedByParticipant() throws Exception {
        RegisteredUser alice = register("alice_att_audio_dl", "alice.att.audio.dl@example.com");
        RegisteredUser bob = register("bob_att_audio_dl", "bob.att.audio.dl@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        byte[] originalBytes = fakeWavBytes(2048);
        MockMultipartFile file = new MockMultipartFile("file", "voice.wav", "audio/wav", originalBytes);
        MvcResult uploadResult = mockMvc.perform(multipart("/api/chats/" + chatId + "/attachments")
                        .file(file)
                        .param("durationSeconds", "3")
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isCreated())
                .andReturn();
        UUID attachmentId = UUID.fromString(
                jsonMapper.readTree(uploadResult.getResponse().getContentAsString()).get("id").asString());

        sendMessage(alice.token, chatId, null, attachmentId)
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.attachments[0].type").value("AUDIO"))
                .andExpect(jsonPath("$.attachments[0].durationSeconds").value(3));

        mockMvc.perform(get("/api/attachments/" + attachmentId).header("Authorization", "Bearer " + bob.token))
                .andExpect(status().isOk())
                .andExpect(header().string("Content-Type", "audio/wav"))
                .andExpect(content().bytes(originalBytes));
    }

    @Test
    void nonParticipantCannotDownloadAudioMessage() throws Exception {
        RegisteredUser alice = register("alice_att_audio_nop", "alice.att.audio.nop@example.com");
        RegisteredUser bob = register("bob_att_audio_nop", "bob.att.audio.nop@example.com");
        RegisteredUser carol = register("carol_att_audio_nop", "carol.att.audio.nop@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        UUID attachmentId = UUID.fromString(jsonMapper
                .readTree(mockMvc.perform(multipart("/api/chats/" + chatId + "/attachments")
                                .file(new MockMultipartFile("file", "voice.wav", "audio/wav", fakeWavBytes(512)))
                                .header("Authorization", "Bearer " + alice.token))
                        .andExpect(status().isCreated())
                        .andReturn()
                        .getResponse()
                        .getContentAsString())
                .get("id")
                .asString());
        sendMessage(alice.token, chatId, null, attachmentId).andExpect(status().isCreated());

        mockMvc.perform(get("/api/attachments/" + attachmentId).header("Authorization", "Bearer " + carol.token))
                .andExpect(status().isNotFound());
    }

    @Test
    void unsupportedFileTypeIsRejected() throws Exception {
        RegisteredUser alice = register("alice_att_bad", "alice.att.bad@example.com");
        RegisteredUser bob = register("bob_att_bad", "bob.att.bad@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        byte[] textBytes = "this is not media, just plain text".getBytes(StandardCharsets.UTF_8);
        MockMultipartFile file = new MockMultipartFile("file", "notes.txt", "text/plain", textBytes);
        mockMvc.perform(multipart("/api/chats/" + chatId + "/attachments")
                        .file(file)
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isBadRequest());
    }

    @Test
    void spoofedContentTypeDoesNotBypassSniffing() throws Exception {
        RegisteredUser alice = register("alice_att_spoof", "alice.att.spoof@example.com");
        RegisteredUser bob = register("bob_att_spoof", "bob.att.spoof@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        // Client claims image/jpeg, but the actual bytes are plain text - the
        // server must sniff real content, not trust the declared MIME type.
        byte[] textBytes = "not actually a jpeg".getBytes(StandardCharsets.UTF_8);
        MockMultipartFile file = new MockMultipartFile("file", "fake.jpg", "image/jpeg", textBytes);
        mockMvc.perform(multipart("/api/chats/" + chatId + "/attachments")
                        .file(file)
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isBadRequest());
    }

    @Test
    void oversizedImageIsRejected() throws Exception {
        RegisteredUser alice = register("alice_att_toobig", "alice.att.toobig@example.com");
        RegisteredUser bob = register("bob_att_toobig", "bob.att.toobig@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        // A real JPEG magic prefix followed by padding past the 10MB default
        // image limit - detection only needs the prefix, so this reliably
        // exercises the size check without needing a fully valid codestream.
        byte[] oversized = new byte[11 * 1024 * 1024];
        oversized[0] = (byte) 0xFF;
        oversized[1] = (byte) 0xD8;
        oversized[2] = (byte) 0xFF;
        MockMultipartFile file = new MockMultipartFile("file", "huge.jpg", "image/jpeg", oversized);
        mockMvc.perform(multipart("/api/chats/" + chatId + "/attachments")
                        .file(file)
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isPayloadTooLarge());
    }

    @Test
    void emptyUploadIsRejected() throws Exception {
        RegisteredUser alice = register("alice_att_empty", "alice.att.empty@example.com");
        RegisteredUser bob = register("bob_att_empty", "bob.att.empty@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        MockMultipartFile file = new MockMultipartFile("file", "empty.jpg", "image/jpeg", new byte[0]);
        mockMvc.perform(multipart("/api/chats/" + chatId + "/attachments")
                        .file(file)
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isBadRequest());
    }

    // ---- download / thumbnail authorization ----

    @Test
    void participantCanDownloadAttachment() throws Exception {
        RegisteredUser alice = register("alice_att_dl", "alice.att.dl@example.com");
        RegisteredUser bob = register("bob_att_dl", "bob.att.dl@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        UUID attachmentId = uploadImageAndGetId(alice.token, chatId, 200, 150);
        sendMessageWithAttachment(alice.token, chatId, attachmentId).andExpect(status().isCreated());

        mockMvc.perform(get("/api/attachments/" + attachmentId).header("Authorization", "Bearer " + bob.token))
                .andExpect(status().isOk())
                .andExpect(header().string("Content-Type", "image/jpeg"));
    }

    @Test
    void videoDownloadSupportsRangeRequestsForSeeking() throws Exception {
        RegisteredUser alice = register("alice_att_vidrange", "alice.att.vidrange@example.com");
        RegisteredUser bob = register("bob_att_vidrange", "bob.att.vidrange@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        byte[] videoBytes = fakeMp4Bytes(4096);
        MockMultipartFile file = new MockMultipartFile("file", "clip.mp4", "video/mp4", videoBytes);
        MvcResult uploadResult = mockMvc.perform(multipart("/api/chats/" + chatId + "/attachments")
                        .file(file)
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isCreated())
                .andReturn();
        UUID attachmentId = UUID.fromString(
                jsonMapper.readTree(uploadResult.getResponse().getContentAsString()).get("id").asString());
        sendMessage(alice.token, chatId, null, attachmentId).andExpect(status().isCreated());

        // No Range header - how a player first fetches the resource.
        mockMvc.perform(get("/api/attachments/" + attachmentId).header("Authorization", "Bearer " + bob.token))
                .andExpect(status().isOk())
                .andExpect(header().string("Content-Type", "video/mp4"))
                .andExpect(header().string("Accept-Ranges", "bytes"))
                .andExpect(header().string("Content-Length", String.valueOf(videoBytes.length)))
                .andExpect(content().bytes(videoBytes));

        // A partial range request - what seeking triggers - must return exactly
        // that slice, decrypted, with correct 206/Content-Range bookkeeping.
        MvcResult rangeResult = mockMvc.perform(get("/api/attachments/" + attachmentId)
                        .header("Authorization", "Bearer " + bob.token)
                        .header("Range", "bytes=100-199"))
                .andExpect(status().isPartialContent())
                .andExpect(header().string("Content-Range", "bytes 100-199/" + videoBytes.length))
                .andExpect(header().string("Content-Length", "100"))
                .andReturn();
        assertArrayEquals(
                Arrays.copyOfRange(videoBytes, 100, 200), rangeResult.getResponse().getContentAsByteArray());
    }

    @Test
    void nonParticipantCannotDownloadAttachment() throws Exception {
        RegisteredUser alice = register("alice_att_nodl", "alice.att.nodl@example.com");
        RegisteredUser bob = register("bob_att_nodl", "bob.att.nodl@example.com");
        RegisteredUser carol = register("carol_att_nodl", "carol.att.nodl@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        UUID attachmentId = uploadImageAndGetId(alice.token, chatId, 200, 150);
        sendMessageWithAttachment(alice.token, chatId, attachmentId).andExpect(status().isCreated());

        mockMvc.perform(get("/api/attachments/" + attachmentId).header("Authorization", "Bearer " + carol.token))
                .andExpect(status().isNotFound());
    }

    @Test
    void guessingAnAttachmentIdDoesNotBypassAuthorization() throws Exception {
        RegisteredUser alice = register("alice_att_guess", "alice.att.guess@example.com");

        mockMvc.perform(get("/api/attachments/" + UUID.randomUUID()).header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isNotFound());
    }

    @Test
    void attachmentDownloadRequiresAuthentication() throws Exception {
        mockMvc.perform(get("/api/attachments/" + UUID.randomUUID())).andExpect(status().isUnauthorized());
    }

    @Test
    void thumbnailIsGeneratedAndAccessibleForLargeImages() throws Exception {
        RegisteredUser alice = register("alice_att_thumb", "alice.att.thumb@example.com");
        RegisteredUser bob = register("bob_att_thumb", "bob.att.thumb@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        MvcResult uploadResult = uploadImage(alice.token, chatId, 1200, 900)
                .andExpect(status().isCreated())
                .andReturn();
        var node = jsonMapper.readTree(uploadResult.getResponse().getContentAsString());
        UUID attachmentId = UUID.fromString(node.get("id").asString());
        String thumbnailUrl = node.get("thumbnailUrl").asString();
        assertEquals("/api/attachments/" + attachmentId + "/thumbnail", thumbnailUrl);

        sendMessageWithAttachment(alice.token, chatId, attachmentId).andExpect(status().isCreated());

        mockMvc.perform(get(thumbnailUrl).header("Authorization", "Bearer " + bob.token))
                .andExpect(status().isOk())
                .andExpect(header().string("Content-Type", "image/jpeg"));
    }

    // ---- sending messages with attachments ----

    @Test
    void imageOnlyMessageWorks() throws Exception {
        RegisteredUser alice = register("alice_att_imgonly", "alice.att.imgonly@example.com");
        RegisteredUser bob = register("bob_att_imgonly", "bob.att.imgonly@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        UUID attachmentId = uploadImageAndGetId(alice.token, chatId, 100, 100);

        sendMessage(alice.token, chatId, null, attachmentId)
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.content").value(""))
                .andExpect(jsonPath("$.attachments", hasSize(1)))
                .andExpect(jsonPath("$.attachments[0].id").value(attachmentId.toString()));
    }

    @Test
    void textPlusAttachmentWorks() throws Exception {
        RegisteredUser alice = register("alice_att_both", "alice.att.both@example.com");
        RegisteredUser bob = register("bob_att_both", "bob.att.both@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        UUID attachmentId = uploadImageAndGetId(alice.token, chatId, 100, 100);

        sendMessage(alice.token, chatId, "Check this out", attachmentId)
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.content").value("Check this out"))
                .andExpect(jsonPath("$.attachments", hasSize(1)));
    }

    @Test
    void videoMessageWorks() throws Exception {
        RegisteredUser alice = register("alice_att_vidmsg", "alice.att.vidmsg@example.com");
        RegisteredUser bob = register("bob_att_vidmsg", "bob.att.vidmsg@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        MockMultipartFile file = new MockMultipartFile("file", "clip.mp4", "video/mp4", fakeMp4Bytes(4096));
        MvcResult uploadResult = mockMvc.perform(multipart("/api/chats/" + chatId + "/attachments")
                        .file(file)
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isCreated())
                .andReturn();
        UUID attachmentId = UUID.fromString(
                jsonMapper.readTree(uploadResult.getResponse().getContentAsString()).get("id").asString());

        sendMessage(alice.token, chatId, null, attachmentId)
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.attachments[0].type").value("VIDEO"));
    }

    @Test
    void messageWithNeitherContentNorAttachmentIsRejected() throws Exception {
        RegisteredUser alice = register("alice_att_neither", "alice.att.neither@example.com");
        RegisteredUser bob = register("bob_att_neither", "bob.att.neither@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        mockMvc.perform(post("/api/chats/" + chatId + "/messages")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(jsonMapper.writeValueAsString(new SendPayload(null, null)))
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isBadRequest());
    }

    @Test
    void anotherUsersPendingAttachmentCannotBeAttached() throws Exception {
        RegisteredUser alice = register("alice_att_steal", "alice.att.steal@example.com");
        RegisteredUser bob = register("bob_att_steal", "bob.att.steal@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        UUID bobsAttachmentId = uploadImageAndGetId(bob.token, chatId, 50, 50);

        sendMessage(alice.token, chatId, "stolen?", bobsAttachmentId).andExpect(status().isBadRequest());
    }

    @Test
    void alreadyAttachedAttachmentCannotBeReused() throws Exception {
        RegisteredUser alice = register("alice_att_reuse", "alice.att.reuse@example.com");
        RegisteredUser bob = register("bob_att_reuse", "bob.att.reuse@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        UUID attachmentId = uploadImageAndGetId(alice.token, chatId, 50, 50);
        sendMessage(alice.token, chatId, "first", attachmentId).andExpect(status().isCreated());

        sendMessage(alice.token, chatId, "second", attachmentId).andExpect(status().isBadRequest());
    }

    // ---- delete ----

    @Test
    void deletedMessageAttachmentIsInaccessible() throws Exception {
        RegisteredUser alice = register("alice_att_del", "alice.att.del@example.com");
        RegisteredUser bob = register("bob_att_del", "bob.att.del@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        UUID attachmentId = uploadImageAndGetId(alice.token, chatId, 100, 100);
        MvcResult sendResult = sendMessage(alice.token, chatId, "temp", attachmentId)
                .andExpect(status().isCreated())
                .andReturn();
        UUID messageId = UUID.fromString(
                jsonMapper.readTree(sendResult.getResponse().getContentAsString()).get("id").asString());

        mockMvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete(
                        "/api/chats/" + chatId + "/messages/" + messageId)
                        .header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isNoContent());

        mockMvc.perform(get("/api/attachments/" + attachmentId).header("Authorization", "Bearer " + alice.token))
                .andExpect(status().isNotFound());
        mockMvc.perform(get("/api/attachments/" + attachmentId).header("Authorization", "Bearer " + bob.token))
                .andExpect(status().isNotFound());
    }

    // ---- pagination ----

    @Test
    void attachmentsAppearCorrectlyInPaginatedResponses() throws Exception {
        RegisteredUser alice = register("alice_att_page", "alice.att.page@example.com");
        RegisteredUser bob = register("bob_att_page", "bob.att.page@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        sendMessage(alice.token, chatId, "text only", null).andExpect(status().isCreated());
        UUID attachmentId = uploadImageAndGetId(alice.token, chatId, 80, 60);
        sendMessage(alice.token, chatId, "with image", attachmentId).andExpect(status().isCreated());

        mockMvc.perform(get("/api/chats/" + chatId + "/messages").header("Authorization", "Bearer " + bob.token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.messages", hasSize(2)))
                .andExpect(jsonPath("$.messages[0].attachments", hasSize(0)))
                .andExpect(jsonPath("$.messages[1].attachments", hasSize(1)))
                .andExpect(jsonPath("$.messages[1].attachments[0].id").value(attachmentId.toString()));
    }

    // ---- chat list preview ----

    @Test
    void chatListPreviewIndicatesAttachmentType() throws Exception {
        RegisteredUser alice = register("alice_att_preview", "alice.att.preview@example.com");
        RegisteredUser bob = register("bob_att_preview", "bob.att.preview@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);
        UUID attachmentId = uploadImageAndGetId(alice.token, chatId, 80, 60);
        sendMessage(alice.token, chatId, null, attachmentId).andExpect(status().isCreated());

        mockMvc.perform(get("/api/chats").header("Authorization", "Bearer " + bob.token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].lastMessage.attachmentType").value("IMAGE"));
    }

    // ---- security ----

    @Test
    void storageKeyIsNeverExposedInApiResponses() throws Exception {
        RegisteredUser alice = register("alice_att_nokey", "alice.att.nokey@example.com");
        RegisteredUser bob = register("bob_att_nokey", "bob.att.nokey@example.com");
        UUID chatId = becomeContactsAndGetChatId(alice, bob);

        MvcResult result = uploadImage(alice.token, chatId, 40, 40).andReturn();
        String body = result.getResponse().getContentAsString();
        assertFalse(body.contains("storageKey"), "response leaked an internal storage key field");
        assertFalse(body.contains("storage_key"));

        UUID attachmentId = UUID.fromString(jsonMapper.readTree(body).get("id").asString());
        MessageAttachment stored = attachmentRepository.findById(attachmentId).orElseThrow();
        assertFalse(body.contains(stored.getStorageKey()), "response leaked the raw storage file name");
    }

    // ---- helpers ----

    private UUID becomeContactsAndGetChatId(RegisteredUser sender, RegisteredUser recipient) throws Exception {
        UUID invitationId = sendInvitationAndGetId(sender.token, recipient.id);
        mockMvc.perform(post("/api/contacts/invitations/" + invitationId + "/accept")
                        .header("Authorization", "Bearer " + recipient.token))
                .andExpect(status().isOk());

        boolean senderIsLower = sender.id.toString().compareTo(recipient.id.toString()) < 0;
        UUID low = senderIsLower ? sender.id : recipient.id;
        UUID high = senderIsLower ? recipient.id : sender.id;
        return conversationRepository.findByDirectUserAIdAndDirectUserBId(low, high).orElseThrow().getId();
    }

    private ResultActions uploadImage(String token, UUID chatId, int width, int height) throws Exception {
        MockMultipartFile file = new MockMultipartFile("file", "pic.jpg", "image/jpeg", jpegBytes(width, height));
        return mockMvc.perform(multipart("/api/chats/" + chatId + "/attachments")
                .file(file)
                .header("Authorization", "Bearer " + token));
    }

    private UUID uploadImageAndGetId(String token, UUID chatId, int width, int height) throws Exception {
        MvcResult result = uploadImage(token, chatId, width, height).andExpect(status().isCreated()).andReturn();
        return UUID.fromString(
                jsonMapper.readTree(result.getResponse().getContentAsString()).get("id").asString());
    }

    private ResultActions sendMessageWithAttachment(String token, UUID chatId, UUID attachmentId) throws Exception {
        return sendMessage(token, chatId, "shared", attachmentId);
    }

    private ResultActions sendMessage(String token, UUID chatId, String content, UUID attachmentId) throws Exception {
        var attachmentIds = attachmentId == null ? null : java.util.List.of(attachmentId);
        return mockMvc.perform(post("/api/chats/" + chatId + "/messages")
                .contentType(MediaType.APPLICATION_JSON)
                .content(jsonMapper.writeValueAsString(new SendPayload(content, attachmentIds)))
                .header("Authorization", "Bearer " + token));
    }

    private UUID sendInvitationAndGetId(String senderToken, UUID recipientId) throws Exception {
        String body = jsonMapper.writeValueAsString(new SendInvitationPayload(recipientId));
        MockHttpServletRequestBuilder request = post("/api/contacts/invitations")
                .contentType(MediaType.APPLICATION_JSON)
                .content(body)
                .header("Authorization", "Bearer " + senderToken);
        MvcResult result = mockMvc.perform(request).andExpect(status().isCreated()).andReturn();
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

    private static byte[] jpegBytes(int width, int height) throws IOException {
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        Graphics2D graphics = image.createGraphics();
        graphics.setColor(Color.BLUE);
        graphics.fillRect(0, 0, width, height);
        graphics.dispose();
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageIO.write(image, "jpg", out);
        return out.toByteArray();
    }

    private static byte[] pngBytes(int width, int height) throws IOException {
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        Graphics2D graphics = image.createGraphics();
        graphics.setColor(Color.GREEN);
        graphics.fillRect(0, 0, width, height);
        graphics.dispose();
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageIO.write(image, "png", out);
        return out.toByteArray();
    }

    /** Enough of an ISO-base-media-file "ftyp" box for {@code AttachmentValidator} to recognize it as MP4. */
    private static byte[] fakeMp4Bytes(int totalSize) {
        byte[] content = new byte[Math.max(totalSize, 16)];
        byte[] header = {0, 0, 0, 0x18, 'f', 't', 'y', 'p', 'i', 's', 'o', 'm', 0, 0, 0, 0};
        System.arraycopy(header, 0, content, 0, header.length);
        Arrays.fill(content, header.length, content.length, (byte) 0);
        return content;
    }

    /** A minimal RIFF/WAVE header (what {@code AttachmentValidator} sniffs) padded to the given size. */
    private static byte[] fakeWavBytes(int totalSize) {
        byte[] content = new byte[Math.max(totalSize, 12)];
        byte[] header = {'R', 'I', 'F', 'F', 0, 0, 0, 0, 'W', 'A', 'V', 'E'};
        System.arraycopy(header, 0, content, 0, header.length);
        Arrays.fill(content, header.length, content.length, (byte) 0);
        return content;
    }

    private record RegisteredUser(UUID id, String token) {
    }

    private record RegisterPayload(String username, String email, String password) {
    }

    private record SendInvitationPayload(UUID recipientId) {
    }

    private record SendPayload(String content, java.util.List<UUID> attachmentIds) {
    }
}
