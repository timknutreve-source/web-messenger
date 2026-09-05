package com.mobilemessenger.backend.security.encryption.exception;

/**
 * Base type for application-level encryption failures. Messages on
 * exceptions in this hierarchy must never include plaintext content, key
 * material, or ciphertext - only enough context to diagnose the failure
 * class (e.g. "tampered", "wrong key", "malformed input").
 */
public class EncryptionException extends RuntimeException {

    public EncryptionException(String message) {
        super(message);
    }

    public EncryptionException(String message, Throwable cause) {
        super(message, cause);
    }
}
