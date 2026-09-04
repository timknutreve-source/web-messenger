package com.mobilemessenger.backend.contact.exception;

public class DuplicateInvitationException extends RuntimeException {

    public DuplicateInvitationException() {
        super("An invitation is already pending");
    }
}
