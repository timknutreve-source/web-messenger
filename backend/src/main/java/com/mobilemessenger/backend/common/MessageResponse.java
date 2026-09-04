package com.mobilemessenger.backend.common;

/** Generic success-message body for endpoints that don't return a resource. */
public record MessageResponse(String message) {
}
