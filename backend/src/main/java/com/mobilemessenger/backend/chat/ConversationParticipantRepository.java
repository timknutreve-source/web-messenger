package com.mobilemessenger.backend.chat;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ConversationParticipantRepository extends JpaRepository<ConversationParticipant, UUID> {

    Optional<ConversationParticipant> findByConversationIdAndUserId(UUID conversationId, UUID userId);

    List<ConversationParticipant> findByUserIdAndArchived(UUID userId, boolean archived);

    /** Every member of one conversation (a group's member list, or the recipients of a group message). */
    List<ConversationParticipant> findByConversationId(UUID conversationId);

    /** Member counts for a batch of conversations, as {@code [conversationId, count]} rows. */
    @org.springframework.data.jpa.repository.Query(
            "SELECT p.conversationId, COUNT(p) FROM ConversationParticipant p "
                    + "WHERE p.conversationId IN :conversationIds GROUP BY p.conversationId")
    List<Object[]> countByConversationIds(
            @org.springframework.data.repository.query.Param("conversationIds") List<UUID> conversationIds);
}
