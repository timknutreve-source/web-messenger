package com.mobilemessenger.backend.chat.dto;

import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;

/**
 * {@code content} is optional (an image/video-only message has none), but a
 * message must end up with content or at least one attachment - enforced in
 * {@code MessageService}, since that's a cross-field rule bean validation
 * doesn't express cleanly.
 */
public record SendMessageRequest(
        @Size(max = 4000, message = "Message is too long") String content, List<UUID> attachmentIds) {}
