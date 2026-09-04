package com.mobilemessenger.backend.contact.dto;

import java.time.Instant;
import java.util.UUID;

public record ContactInvitationResponse(
        UUID id,
        ContactUserSummary sender,
        ContactUserSummary recipient,
        String status,
        Instant createdAt,
        Instant respondedAt
) {
}
