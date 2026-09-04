package com.mobilemessenger.backend.auth.token;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.HexFormat;

/**
 * Generates the random tokens used for email verification and password
 * reset links, and hashes them for storage.
 *
 * The raw token is only ever held in memory and sent to the user by email -
 * it is never persisted. Only {@link #hash(String)} of it is stored, so a
 * database read alone can never yield a usable token. SHA-256 (not BCrypt)
 * is used here deliberately: unlike passwords, these tokens are already
 * high-entropy random values, so a fast deterministic hash is both safe and
 * necessary for an indexed exact-match lookup by hash.
 */
public final class SecureTokenGenerator {

    private static final SecureRandom RANDOM = new SecureRandom();
    private static final int TOKEN_BYTES = 32;

    private SecureTokenGenerator() {
    }

    public static String generate() {
        byte[] bytes = new byte[TOKEN_BYTES];
        RANDOM.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    public static String hash(String rawToken) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hashed = digest.digest(rawToken.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(hashed);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 is not available", e);
        }
    }
}
