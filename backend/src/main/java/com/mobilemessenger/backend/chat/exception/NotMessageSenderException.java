package com.mobilemessenger.backend.chat.exception;

/** Thrown when a user tries to edit or delete a message they didn't send. */
public class NotMessageSenderException extends RuntimeException {
    public NotMessageSenderException() {
        super("You can only modify your own messages");
    }
}
