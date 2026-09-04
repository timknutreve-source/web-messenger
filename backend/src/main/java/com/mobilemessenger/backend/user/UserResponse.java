package com.mobilemessenger.backend.user;

import java.time.Instant;
import java.util.UUID;

/**
 * Safe, public view of a {@link User}. Never includes the password hash.
 *
 * Shared by the auth feature (registration/login/{@code /me}) and the profile
 * feature, since both ultimately expose the same underlying account data.
 */
public record UserResponse(
        UUID id,
        String username,
        String email,
        boolean emailVerified,
        String aboutMe,
        String avatarFileName,
        Instant createdAt
) {

    public static UserResponse from(User user) {
        return new UserResponse(
                user.getId(),
                user.getUsername(),
                user.getEmail(),
                user.isEmailVerified(),
                user.getAboutMe(),
                user.getAvatarFileName(),
                user.getCreatedAt());
    }
}
