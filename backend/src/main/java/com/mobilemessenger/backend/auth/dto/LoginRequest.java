package com.mobilemessenger.backend.auth.dto;

import jakarta.validation.constraints.NotBlank;

public record LoginRequest(
        @NotBlank(message = "Username or email is required")
        String usernameOrEmail,

        @NotBlank(message = "Password is required")
        String password,

        /** Optional, e.g. "Web" or "Android" - shown in the active-sessions list. */
        String deviceName
) {
}
