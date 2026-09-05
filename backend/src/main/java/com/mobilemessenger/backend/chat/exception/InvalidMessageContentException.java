package com.mobilemessenger.backend.chat.exception;

/** Thrown when a message would have neither text content nor any attachment. */
public class InvalidMessageContentException extends RuntimeException {
    public InvalidMessageContentException() {
        super("A message must have text content or at least one attachment");
    }
}
