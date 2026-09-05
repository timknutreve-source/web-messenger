package com.mobilemessenger.backend.chat;

/**
 * The application-level lifecycle of a message, distinct from any
 * WebSocket-transport-level delivery semantics: SENT the moment it's
 * persisted, DELIVERED once the recipient's client acknowledges receiving
 * it, READ once the recipient opens the conversation.
 */
public enum MessageStatus {
    SENT,
    DELIVERED,
    READ
}
