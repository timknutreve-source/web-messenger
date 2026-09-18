package com.mobilemessenger.backend.auth.dto;

import com.mobilemessenger.backend.auth.validation.StrongPassword;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record ResetPasswordRequest(
        @NotBlank(message = "Email is required")
        @Email(message = "Email must be a valid email address")
        String email,

        @NotBlank(message = "Code is required")
        @Pattern(regexp = "^\\d{6}$", message = "Code must be 6 digits")
        String code,

        @NotBlank(message = "Password is required")
        @Size(max = 72, message = "Password must be at most 72 characters")
        @StrongPassword
        String newPassword
) {
}
