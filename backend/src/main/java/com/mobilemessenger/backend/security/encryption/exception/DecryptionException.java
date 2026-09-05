package com.mobilemessenger.backend.security.encryption.exception;

/**
 * Thrown when ciphertext cannot be decrypted: malformed/truncated input,
 * an unsupported envelope version, or GCM authentication failure (wrong
 * key or tampered data - AES-GCM cannot tell these apart, which is exactly
 * the point of an authenticated cipher).
 */
public class DecryptionException extends EncryptionException {

    public DecryptionException(String message) {
        super(message);
    }

    public DecryptionException(String message, Throwable cause) {
        super(message, cause);
    }
}
