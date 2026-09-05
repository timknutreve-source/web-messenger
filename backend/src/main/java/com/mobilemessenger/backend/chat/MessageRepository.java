package com.mobilemessenger.backend.chat;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface MessageRepository extends JpaRepository<Message, UUID> {

    Optional<Message> findByIdAndConversationId(UUID id, UUID conversationId);

    /** Most recent page (no cursor yet) - newest first, capped by {@code pageable}'s page size. */
    List<Message> findByConversationIdOrderByCreatedAtDescIdDesc(UUID conversationId, Pageable pageable);

    /**
     * Keyset pagination for older pages: everything strictly before the
     * given (createdAt, id) cursor, newest-of-the-remainder first. Using a
     * compound cursor (rather than createdAt alone) keeps ordering stable
     * even when two messages share a timestamp.
     */
    @Query("SELECT m FROM Message m WHERE m.conversationId = :conversationId "
            + "AND (m.createdAt < :beforeCreatedAt OR (m.createdAt = :beforeCreatedAt AND m.id < :beforeId)) "
            + "ORDER BY m.createdAt DESC, m.id DESC")
    List<Message> findPageBefore(
            @Param("conversationId") UUID conversationId,
            @Param("beforeCreatedAt") Instant beforeCreatedAt,
            @Param("beforeId") UUID beforeId,
            Pageable pageable);

    /** Every message in the conversation not sent by {@code userId} that isn't already READ. */
    List<Message> findByConversationIdAndSenderIdNotAndStatusNot(
            UUID conversationId, UUID userId, MessageStatus status);

    /** The single most recent message in the conversation, for chat-list previews. */
    Optional<Message> findFirstByConversationIdOrderByCreatedAtDescIdDesc(UUID conversationId);
}
