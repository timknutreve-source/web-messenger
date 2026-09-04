package com.mobilemessenger.backend.auth.dto;

import com.mobilemessenger.backend.auth.validation.StrongPassword;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record ResetPasswordRequest(
        @NotBlank(message = "Token is required")
        String token,

        @NotBlank(message = "Password is required")
        @Size(max = 72, message = "Password must be at most 72 characters")
        @StrongPassword
        String newPassword
) {
}
