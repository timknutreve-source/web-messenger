package com.mobilemessenger.backend.contact.dto;

import java.time.Instant;
import java.util.UUID;

public record PendingInvitationResponse(
        UUID id,
        ContactUserSummary sender,
        Instant createdAt
) {
}
