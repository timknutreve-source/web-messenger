package com.mobilemessenger.backend.chat.dto;

import com.mobilemessenger.backend.contact.dto.ContactUserSummary;
import java.time.Instant;
import java.util.UUID;

public record ChatSummaryResponse(
        UUID id,
        ContactUserSummary otherUser,
        Instant lastActivityAt,
        boolean archived,
        MessagePreviewResponse lastMessage,
        int unreadCount) {}
