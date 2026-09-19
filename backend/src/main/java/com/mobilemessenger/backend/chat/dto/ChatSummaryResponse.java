package com.mobilemessenger.backend.chat.dto;

import com.mobilemessenger.backend.contact.dto.ContactUserSummary;
import java.time.Instant;
import java.util.UUID;

/**
 * One row of the chat list. {@code type} is {@code DIRECT} or {@code GROUP}:
 * a direct chat is identified by {@code otherUser} (null for a group), a
 * group by its {@code name} and {@code memberCount} (both null/0 for a
 * direct chat).
 */
public record ChatSummaryResponse(
        UUID id,
        String type,
        ContactUserSummary otherUser,
        String name,
        int memberCount,
        Instant lastActivityAt,
        boolean archived,
        MessagePreviewResponse lastMessage,
        int unreadCount) {}
