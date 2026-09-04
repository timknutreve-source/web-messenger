package com.mobilemessenger.backend.contact.dto;

import com.mobilemessenger.backend.user.User;
import java.util.UUID;

/**
 * Minimal safe public view of a user for search results, invitations, and
 * contact lists - deliberately narrower than {@link com.mobilemessenger.backend.user.UserResponse}
 * (no {@code emailVerified}/{@code aboutMe}/{@code createdAt}: this feature's
 * UI has no use for them).
 */
public record ContactUserSummary(UUID id, String username, String email, String avatarFileName) {

    public static ContactUserSummary from(User user) {
        return new ContactUserSummary(user.getId(), user.getUsername(), user.getEmail(), user.getAvatarFileName());
    }
}
