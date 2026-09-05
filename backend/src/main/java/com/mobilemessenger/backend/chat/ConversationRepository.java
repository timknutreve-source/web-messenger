package com.mobilemessenger.backend.chat;

import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ConversationRepository extends JpaRepository<Conversation, UUID> {

    Optional<Conversation> findByDirectUserAIdAndDirectUserBId(UUID directUserAId, UUID directUserBId);
}
