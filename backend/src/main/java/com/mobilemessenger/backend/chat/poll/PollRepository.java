package com.mobilemessenger.backend.chat.poll;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface PollRepository extends JpaRepository<Poll, UUID> {

    Optional<Poll> findByIdAndConversationId(UUID id, UUID conversationId);

    List<Poll> findByMessageIdIn(Collection<UUID> messageIds);
}
