package com.mobilemessenger.backend.chat.exception;

/** Thrown when a user tries to acknowledge delivery of their own message. */
public class CannotActOnOwnMessageException extends RuntimeException {
    public CannotActOnOwnMessageException() {
        super("You cannot acknowledge your own message");
    }
}
