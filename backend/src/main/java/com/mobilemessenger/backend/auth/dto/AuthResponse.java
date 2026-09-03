package com.mobilemessenger.backend.auth.dto;

public record AuthResponse(String token, UserResponse user) {
}
