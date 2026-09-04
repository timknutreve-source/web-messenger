package com.mobilemessenger.backend.profile.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record UpdateProfileRequest(
        @NotBlank(message = "Username is required")
        @Size(min = 3, max = 30, message = "Username must be between 3 and 30 characters")
        @Pattern(
                regexp = "^[a-zA-Z0-9_.-]+$",
                message = "Username may only contain letters, digits, '.', '_' and '-'")
        String username,

        @NotBlank(message = "Email is required")
        @Email(message = "Email must be a valid email address")
        String email,

        @Size(max = 500, message = "About Me must be at most 500 characters")
        String aboutMe
) {
}
