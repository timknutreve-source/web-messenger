package com.mobilemessenger.backend.user.exception;

public class DuplicateEmailException extends RuntimeException {

    public DuplicateEmailException() {
        super("Email is already registered");
    }
}
