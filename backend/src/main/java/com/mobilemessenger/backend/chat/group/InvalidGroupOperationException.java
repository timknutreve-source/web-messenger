package com.mobilemessenger.backend.chat.group;

/** A group request that is well-formed but not allowed (e.g. inviting someone who isn't your contact). */
public class InvalidGroupOperationException extends RuntimeException {

    public InvalidGroupOperationException(String message) {
        super(message);
    }
}
