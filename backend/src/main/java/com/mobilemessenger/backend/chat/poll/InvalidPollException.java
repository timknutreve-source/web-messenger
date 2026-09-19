package com.mobilemessenger.backend.chat.poll;

/** A poll request that is well-formed but not allowed (wrong chat type, bad options, closed by deletion...). */
public class InvalidPollException extends RuntimeException {

    public InvalidPollException(String message) {
        super(message);
    }
}
