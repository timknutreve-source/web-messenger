package com.mobilemessenger.backend.contact.exception;

public class AlreadyContactsException extends RuntimeException {

    public AlreadyContactsException() {
        super("You are already contacts");
    }
}
