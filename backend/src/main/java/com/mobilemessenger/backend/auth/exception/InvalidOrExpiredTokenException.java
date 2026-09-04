package com.mobilemessenger.backend.auth.exception;

/**
 * Thrown for a token that is unknown, expired, or already used - all three
 * cases return the same generic message so a caller can't distinguish
 * "wrong token" from "expired" from "already used" by probing.
 */
public class InvalidOrExpiredTokenException extends RuntimeException {

    public InvalidOrExpiredTokenException() {
        super("This link is invalid or has expired. Please request a new one.");
    }
}
