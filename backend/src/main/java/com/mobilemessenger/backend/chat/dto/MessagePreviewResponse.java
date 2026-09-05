package com.mobilemessenger.backend.chat.dto;

import com.mobilemessenger.backend.chat.Message;
import java.time.Instant;
import java.util.UUID;

/** A lightweight preview of a conversation's most recent message, for the chat list. */
public record MessagePreviewResponse(UUID id, String content, UUID senderId, Instant createdAt, boolean deleted) {

    public static MessagePreviewResponse from(Message message) {
        return new MessagePreviewResponse(
                message.getId(),
                message.isDeleted() ? null : message.getContent(),
                message.getSenderId(),
                message.getCreatedAt(),
                message.isDeleted());
    }
}
