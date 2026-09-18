package com.mobilemessenger.backend.auth.exception;

/**
 * Thrown for a code that is unknown, wrong, expired, already used, or over
 * its attempt limit - every case returns the same generic message so a
 * caller can't distinguish one from another by probing (including, for
 * password reset, whether the email address is even registered).
 */
public class InvalidOrExpiredTokenException extends RuntimeException {

    public InvalidOrExpiredTokenException() {
        super("This code is invalid or has expired. Please request a new one.");
    }
}
