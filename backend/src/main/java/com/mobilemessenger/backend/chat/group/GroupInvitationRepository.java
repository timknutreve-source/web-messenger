package com.mobilemessenger.backend.chat.group;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface GroupInvitationRepository extends JpaRepository<GroupInvitation, UUID> {

    List<GroupInvitation> findByInviteeIdAndStatusOrderByCreatedAtDesc(UUID inviteeId, GroupInvitationStatus status);

    List<GroupInvitation> findByConversationIdAndStatus(UUID conversationId, GroupInvitationStatus status);

    Optional<GroupInvitation> findByConversationIdAndInviteeIdAndStatus(
            UUID conversationId, UUID inviteeId, GroupInvitationStatus status);
}
