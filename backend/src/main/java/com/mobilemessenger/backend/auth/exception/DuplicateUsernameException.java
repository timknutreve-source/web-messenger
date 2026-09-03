package com.mobilemessenger.backend.auth.exception;

public class DuplicateUsernameException extends RuntimeException {

    public DuplicateUsernameException() {
        super("Username is already taken");
    }
}
