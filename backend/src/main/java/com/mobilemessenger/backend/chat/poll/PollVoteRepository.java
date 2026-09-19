package com.mobilemessenger.backend.chat.poll;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface PollVoteRepository extends JpaRepository<PollVote, UUID> {

    Optional<PollVote> findByPollIdAndUserId(UUID pollId, UUID userId);

    List<PollVote> findByPollIdInOrderByVotedAtAsc(Collection<UUID> pollIds);
}
