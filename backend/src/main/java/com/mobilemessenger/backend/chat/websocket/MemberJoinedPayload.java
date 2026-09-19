package com.mobilemessenger.backend.chat.websocket;

import java.util.UUID;

/** Payload of the {@code MEMBER_JOINED} chat event: someone accepted their invitation to the group. */
public record MemberJoinedPayload(UUID userId, String username) {}
