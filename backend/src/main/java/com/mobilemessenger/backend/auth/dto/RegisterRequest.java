package com.mobilemessenger.backend.auth.dto;

import com.mobilemessenger.backend.auth.validation.StrongPassword;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record RegisterRequest(
        @NotBlank(message = "Username is required")
        @Size(min = 3, max = 30, message = "Username must be between 3 and 30 characters")
        @Pattern(
                regexp = "^[a-zA-Z0-9_.-]+$",
                message = "Username may only contain letters, digits, '.', '_' and '-'")
        String username,

        @NotBlank(message = "Email is required")
        @Email(message = "Email must be a valid email address")
        String email,

        @NotBlank(message = "Password is required")
        @Size(max = 72, message = "Password must be at most 72 characters")
        @StrongPassword
        String password,

        /** Optional, e.g. "Web" or "Android" - shown in the active-sessions list. */
        String deviceName
) {
}
