package com.mobilemessenger.backend.chat;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface MessageReceiptRepository extends JpaRepository<MessageReceipt, UUID> {

    Optional<MessageReceipt> findByMessageIdAndUserId(UUID messageId, UUID userId);

    List<MessageReceipt> findByMessageIdIn(Collection<UUID> messageIds);
}
