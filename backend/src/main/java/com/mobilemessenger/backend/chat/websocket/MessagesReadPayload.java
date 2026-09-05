package com.mobilemessenger.backend.chat.websocket;

import java.util.List;
import java.util.UUID;

public record MessagesReadPayload(List<UUID> messageIds) {}
