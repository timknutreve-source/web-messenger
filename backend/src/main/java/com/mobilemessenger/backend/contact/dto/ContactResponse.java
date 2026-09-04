package com.mobilemessenger.backend.contact.dto;

import java.time.Instant;

public record ContactResponse(
        ContactUserSummary user,
        Instant since
) {
}
