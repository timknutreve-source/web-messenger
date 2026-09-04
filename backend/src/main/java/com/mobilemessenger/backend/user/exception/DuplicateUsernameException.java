package com.mobilemessenger.backend.user.exception;

public class DuplicateUsernameException extends RuntimeException {

    public DuplicateUsernameException() {
        super("Username is already taken");
    }
}
