package com.mobilemessenger.backend.storage.exception;

public class FileTooLargeException extends RuntimeException {

    public FileTooLargeException(String message) {
        super(message);
    }
}
