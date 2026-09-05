package com.mobilemessenger.backend.chat.websocket;

import java.util.UUID;

/** Who is typing - identity always comes from the authenticated STOMP session, never the client payload. */
public record TypingEventPayload(UUID userId, String username) {}
