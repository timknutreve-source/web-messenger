package com.mobilemessenger.backend.chat.group.dto;

import com.mobilemessenger.backend.contact.dto.ContactUserSummary;
import java.time.Instant;
import java.util.UUID;

/** An incoming group invitation, as listed in the recipient's pending-invitations section. */
public record PendingGroupInvitationResponse(
        UUID id, UUID groupId, String groupName, int memberCount, ContactUserSummary inviter, Instant createdAt) {}
