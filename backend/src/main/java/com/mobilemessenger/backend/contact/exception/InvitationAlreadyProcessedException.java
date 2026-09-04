package com.mobilemessenger.backend.contact.exception;

public class InvitationAlreadyProcessedException extends RuntimeException {

    public InvitationAlreadyProcessedException() {
        super("This invitation has already been responded to");
    }
}
