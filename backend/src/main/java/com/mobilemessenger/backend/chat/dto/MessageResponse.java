package com.mobilemessenger.backend.chat.dto;

import com.mobilemessenger.backend.chat.Message;
import com.mobilemessenger.backend.contact.dto.ContactUserSummary;
import com.mobilemessenger.backend.user.User;
import java.time.Instant;
import java.util.UUID;

public record MessageResponse(
        UUID id,
        UUID conversationId,
        ContactUserSummary sender,
        String content,
        String status,
        Instant createdAt,
        Instant editedAt,
        boolean deleted) {

    /** {@code content} is always {@code null} for a deleted message - its original text is never re-exposed. */
    public static MessageResponse from(Message message, User sender) {
        return new MessageResponse(
                message.getId(),
                message.getConversationId(),
                ContactUserSummary.from(sender),
                message.isDeleted() ? null : message.getContent(),
                message.getStatus().name(),
                message.getCreatedAt(),
                message.getEditedAt(),
                message.isDeleted());
    }
}
