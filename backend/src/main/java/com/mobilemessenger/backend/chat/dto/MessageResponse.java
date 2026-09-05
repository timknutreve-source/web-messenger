package com.mobilemessenger.backend.chat.dto;

import com.mobilemessenger.backend.chat.Message;
import com.mobilemessenger.backend.chat.MessageAttachment;
import com.mobilemessenger.backend.contact.dto.ContactUserSummary;
import com.mobilemessenger.backend.user.User;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

public record MessageResponse(
        UUID id,
        UUID conversationId,
        ContactUserSummary sender,
        String content,
        String status,
        Instant createdAt,
        Instant editedAt,
        boolean deleted,
        List<AttachmentResponse> attachments) {

    /**
     * {@code content} and {@code attachments} are always empty for a deleted
     * message - neither its original text nor its media are re-exposed once
     * deleted (the attachment download endpoint independently refuses
     * access to a deleted message's media regardless of what a client
     * already cached from an earlier response).
     */
    public static MessageResponse from(Message message, User sender, List<MessageAttachment> attachments) {
        return new MessageResponse(
                message.getId(),
                message.getConversationId(),
                ContactUserSummary.from(sender),
                message.isDeleted() ? null : message.getContent(),
                message.getStatus().name(),
                message.getCreatedAt(),
                message.getEditedAt(),
                message.isDeleted(),
                message.isDeleted() ? List.of() : attachments.stream().map(AttachmentResponse::from).toList());
    }
}
