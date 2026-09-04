package com.mobilemessenger.backend.contact.exception;

public class SelfInvitationException extends RuntimeException {

    public SelfInvitationException() {
        super("You cannot invite yourself");
    }
}
