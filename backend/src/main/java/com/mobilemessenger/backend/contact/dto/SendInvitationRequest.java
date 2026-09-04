package com.mobilemessenger.backend.contact.dto;

import jakarta.validation.constraints.NotNull;
import java.util.UUID;

public record SendInvitationRequest(
        @NotNull(message = "Recipient is required")
        UUID recipientId
) {
}
