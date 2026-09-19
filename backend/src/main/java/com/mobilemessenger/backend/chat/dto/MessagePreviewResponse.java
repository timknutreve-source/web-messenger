package com.mobilemessenger.backend.chat.dto;

import com.mobilemessenger.backend.chat.Message;
import java.time.Instant;
import java.util.UUID;

/**
 * A lightweight preview of a conversation's most recent message, for the
 * chat list. {@code attachmentType} ({@code "IMAGE"}/{@code "VIDEO"}, or
 * {@code null} for a text-only message) lets the client show something like
 * "Photo"/"Video" instead of - or alongside - {@code content}; the choice of
 * exact wording/emoji is left to the client rather than baked in here.
 */
public record MessagePreviewResponse(
        UUID id,
        String content,
        UUID senderId,
        Instant createdAt,
        boolean deleted,
        String attachmentType,
        String senderUsername) {

    /** {@code senderUsername} is only meaningful in a group's chat list ("alice: see you at 6"). */
    public static MessagePreviewResponse from(Message message, String attachmentType, String senderUsername) {
        return new MessagePreviewResponse(
                message.getId(),
                message.isDeleted() ? null : message.getContent(),
                message.getSenderId(),
                message.getCreatedAt(),
                message.isDeleted(),
                message.isDeleted() ? null : attachmentType,
                senderUsername);
    }
}
