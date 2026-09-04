package com.mobilemessenger.backend.auth.dto;

import com.mobilemessenger.backend.user.UserResponse;

public record AuthResponse(String token, UserResponse user) {
}
