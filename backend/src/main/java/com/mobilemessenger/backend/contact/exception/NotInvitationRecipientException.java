package com.mobilemessenger.backend.contact.exception;

/** Thrown when a user tries to accept/decline an invitation addressed to someone else. */
public class NotInvitationRecipientException extends RuntimeException {

    public NotInvitationRecipientException() {
        super("You are not authorized to respond to this invitation");
    }
}
