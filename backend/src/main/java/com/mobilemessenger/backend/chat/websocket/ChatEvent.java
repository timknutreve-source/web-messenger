package com.mobilemessenger.backend.chat.websocket;

/**
 * Envelope for every event broadcast to {@code /topic/chats/{chatId}}.
 * {@code type} tells the client which shape to expect in {@code payload}:
 * {@code NEW_MESSAGE}/{@code MESSAGE_UPDATED} carry a {@code MessageResponse},
 * {@code MESSAGE_DELETED} a {@link MessageDeletedPayload}, {@code
 * MESSAGE_STATUS_UPDATED} a {@code MessageResponse} (its {@code status}
 * already reflects the change), {@code MESSAGES_READ} a {@link
 * MessagesReadPayload}, and {@code TYPING_STARTED}/{@code TYPING_STOPPED} a
 * {@link TypingEventPayload}.
 */
public record ChatEvent(String type, Object payload) {

    public static ChatEvent of(String type, Object payload) {
        return new ChatEvent(type, payload);
    }
}
