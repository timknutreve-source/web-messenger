package com.mobilemessenger.backend.chat;

import com.mobilemessenger.backend.chat.dto.AttachmentResponse;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

/**
 * Uploads a media file for a conversation, ahead of the message that will
 * carry it: the client uploads first, gets an attachment id back, then
 * sends the message referencing it (see {@code SendMessageRequest}).
 */
@RestController
@RequestMapping("/api/chats/{chatId}/attachments")
public class AttachmentUploadController {

    private final AttachmentService attachmentService;

    public AttachmentUploadController(AttachmentService attachmentService) {
        this.attachmentService = attachmentService;
    }

    @PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<AttachmentResponse> upload(
            Authentication authentication,
            @PathVariable UUID chatId,
            @RequestParam("file") MultipartFile file,
            @RequestParam(value = "durationSeconds", required = false) Integer durationSeconds) {
        AttachmentResponse response =
                attachmentService.upload(chatId, currentUserId(authentication), file, durationSeconds);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    private UUID currentUserId(Authentication authentication) {
        return (UUID) authentication.getPrincipal();
    }
}
