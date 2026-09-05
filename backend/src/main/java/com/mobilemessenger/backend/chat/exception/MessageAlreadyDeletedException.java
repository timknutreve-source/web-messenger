package com.mobilemessenger.backend.chat.exception;

/** Thrown when trying to edit a message that has already been (soft-)deleted. */
public class MessageAlreadyDeletedException extends RuntimeException {
    public MessageAlreadyDeletedException() {
        super("This message has been deleted");
    }
}
