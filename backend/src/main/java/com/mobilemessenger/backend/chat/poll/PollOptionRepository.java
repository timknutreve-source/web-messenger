package com.mobilemessenger.backend.chat.poll;

import java.util.Collection;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface PollOptionRepository extends JpaRepository<PollOption, UUID> {

    List<PollOption> findByPollIdInOrderByPositionAsc(Collection<UUID> pollIds);
}
