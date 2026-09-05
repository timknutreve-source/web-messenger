package com.mobilemessenger.backend.chat.websocket;

import java.util.UUID;

public record MessageDeletedPayload(UUID messageId) {}
