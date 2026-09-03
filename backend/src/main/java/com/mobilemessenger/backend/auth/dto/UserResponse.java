package com.mobilemessenger.backend.auth.dto;

import com.mobilemessenger.backend.user.User;
import java.time.Instant;
import java.util.UUID;

/**
 * Safe, public view of a {@link User}. Never includes the password hash.
 */
public record UserResponse(
        UUID id,
        String username,
        String email,
        boolean emailVerified,
        Instant createdAt
) {

    public static UserResponse from(User user) {
        return new UserResponse(
                user.getId(),
                user.getUsername(),
                user.getEmail(),
                user.isEmailVerified(),
                user.getCreatedAt());
    }
}
