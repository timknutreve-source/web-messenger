package com.mobilemessenger.backend.chat.exception;

/** Thrown when a message references an attachment id that doesn't exist, isn't pending, or isn't the caller's own upload for this conversation. */
public class InvalidAttachmentException extends RuntimeException {
    public InvalidAttachmentException(String message) {
        super(message);
    }
}
