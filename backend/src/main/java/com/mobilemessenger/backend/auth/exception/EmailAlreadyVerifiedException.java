package com.mobilemessenger.backend.auth.exception;

public class EmailAlreadyVerifiedException extends RuntimeException {

    public EmailAlreadyVerifiedException() {
        super("Your email is already verified");
    }
}
