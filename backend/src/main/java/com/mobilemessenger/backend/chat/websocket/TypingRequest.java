package com.mobilemessenger.backend.chat.websocket;

/** Inbound payload for {@code /app/chats/{chatId}/typing}. */
public record TypingRequest(boolean started) {}
