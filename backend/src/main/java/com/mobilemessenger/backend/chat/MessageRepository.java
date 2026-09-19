package com.mobilemessenger.backend.chat;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
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

    /**
     * Status changes are done as single conditional UPDATEs rather than by
     * loading a message and saving it back: a client reports "delivered" and
     * "read" for the same message within milliseconds of each other (the web
     * app does exactly that), and with read-modify-write the slower commit
     * could overwrite READ with DELIVERED. The database applies each
     * atomically and never moves a status backwards.
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("UPDATE Message m SET m.status = com.mobilemessenger.backend.chat.MessageStatus.DELIVERED "
            + "WHERE m.id = :id AND m.status = com.mobilemessenger.backend.chat.MessageStatus.SENT")
    int markDeliveredIfSent(@Param("id") UUID id);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("UPDATE Message m SET m.status = com.mobilemessenger.backend.chat.MessageStatus.READ "
            + "WHERE m.id IN :ids AND m.status <> com.mobilemessenger.backend.chat.MessageStatus.READ")
    int markReadIfNotRead(@Param("ids") List<UUID> ids);

    /** The single most recent message in the conversation, for chat-list previews. */
    Optional<Message> findFirstByConversationIdOrderByCreatedAtDescIdDesc(UUID conversationId);

    /**
     * Per-conversation unread count for the chat list's unread badge - every
     * message not sent by {@code userId} that isn't already READ, the exact
     * same definition of "unread" {@link #findByConversationIdAndSenderIdNotAndStatusNot}
     * uses for marking messages read, just aggregated across every one of
     * the user's conversations in a single query instead of one per chat.
     * Returns {@code [conversationId, count]} pairs; a conversation with no
     * unread messages simply has no row (never a zero-count row).
     */
    @Query("SELECT m.conversationId, COUNT(m) FROM Message m "
            + "WHERE m.conversationId IN :conversationIds AND m.senderId <> :userId AND m.status <> :status "
            + "GROUP BY m.conversationId")
    List<Object[]> countUnreadByConversationIds(
            @Param("conversationIds") List<UUID> conversationIds,
            @Param("userId") UUID userId,
            @Param("status") MessageStatus status);

    /**
     * Group version of {@link #countUnreadByConversationIds}: a group message
     * has no single "read" status (its status only reaches READ once *every*
     * member has read it), so "unread for this user" means "this user has no
     * read receipt for it". Messages sent before the user joined don't count.
     */
    @Query("SELECT m.conversationId, COUNT(m) FROM Message m "
            + "WHERE m.conversationId IN :conversationIds AND m.senderId <> :userId "
            + "AND NOT EXISTS (SELECT r.id FROM MessageReceipt r "
            + "WHERE r.messageId = m.id AND r.userId = :userId AND r.readAt IS NOT NULL) "
            + "AND m.createdAt >= (SELECT p.joinedAt FROM ConversationParticipant p "
            + "WHERE p.conversationId = m.conversationId AND p.userId = :userId) "
            + "GROUP BY m.conversationId")
    List<Object[]> countUnreadInGroups(
            @Param("conversationIds") List<UUID> conversationIds, @Param("userId") UUID userId);

    /** The group messages {@code userId} still has to read - see {@link #countUnreadInGroups}. */
    @Query("SELECT m FROM Message m WHERE m.conversationId = :conversationId AND m.senderId <> :userId "
            + "AND NOT EXISTS (SELECT r.id FROM MessageReceipt r "
            + "WHERE r.messageId = m.id AND r.userId = :userId AND r.readAt IS NOT NULL) "
            + "AND m.createdAt >= (SELECT p.joinedAt FROM ConversationParticipant p "
            + "WHERE p.conversationId = m.conversationId AND p.userId = :userId) "
            + "ORDER BY m.createdAt ASC")
    List<Message> findUnreadInGroup(@Param("conversationId") UUID conversationId, @Param("userId") UUID userId);
}
