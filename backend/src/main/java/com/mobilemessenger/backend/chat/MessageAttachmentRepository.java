package com.mobilemessenger.backend.chat;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface MessageAttachmentRepository extends JpaRepository<MessageAttachment, UUID> {

    /** Batch-fetch for a page of messages, to avoid N+1 queries when building message DTOs. */
    List<MessageAttachment> findByMessageIdIn(List<UUID> messageIds);

    List<MessageAttachment> findByMessageId(UUID messageId);

    /** Used only to tell the chat-list preview whether the last message has an attachment (and of what type). */
    Optional<MessageAttachment> findFirstByMessageId(UUID messageId);
}
