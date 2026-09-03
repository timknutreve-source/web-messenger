package com.mobilemessenger.backend.auth.exception;

/**
 * Thrown for both "user not found" and "wrong password" so the API never
 * reveals which one occurred.
 */
public class InvalidCredentialsException extends RuntimeException {

    public InvalidCredentialsException() {
        super("Invalid credentials");
    }
}
