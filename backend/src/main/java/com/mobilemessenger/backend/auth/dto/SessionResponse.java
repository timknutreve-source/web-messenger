package com.mobilemessenger.backend.auth.dto;

import com.mobilemessenger.backend.auth.session.AuthSession;
import java.time.Instant;
import java.util.UUID;

/** A signed-in device/browser as shown in the "active sessions" list; {@code current} marks the caller's own. */
public record SessionResponse(UUID id, String deviceLabel, Instant createdAt, Instant lastSeenAt, boolean current) {

    public static SessionResponse from(AuthSession session, UUID currentSessionId) {
        return new SessionResponse(
                session.getId(),
                session.getDeviceLabel(),
                session.getCreatedAt(),
                session.getLastSeenAt(),
                session.getId().equals(currentSessionId));
    }
}
