package com.mobilemessenger.backend.auth.token;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.util.HexFormat;

/**
 * Generates the random codes used for email verification and password
 * reset, and hashes them for storage.
 *
 * The raw code is only ever held in memory and sent to the user by email -
 * it is never persisted. Only {@link #hash(String)} of it is stored, so a
 * database read alone can never yield a usable code. SHA-256 (not BCrypt)
 * is used here deliberately: a fast deterministic hash is what an
 * exact-match comparison against a single per-user pending code needs -
 * unlike a password hash, this is never used to defend against an offline
 * dictionary attack over the hash column itself (see {@link
 * com.mobilemessenger.backend.auth.EmailVerificationService} and {@link
 * com.mobilemessenger.backend.auth.PasswordResetService} for the attempt
 * limit that defends the online guessing surface instead, which a 6-digit
 * code's much smaller space than the old 256-bit token needs).
 */
public final class SecureTokenGenerator {

    private static final SecureRandom RANDOM = new SecureRandom();
    private static final int CODE_DIGITS = 6;
    private static final int CODE_BOUND = 1_000_000; // 10^CODE_DIGITS

    private SecureTokenGenerator() {
    }

    /** A random {@value #CODE_DIGITS}-digit numeric code, zero-padded. */
    public static String generateNumericCode() {
        int value = RANDOM.nextInt(CODE_BOUND);
        return String.format("%0" + CODE_DIGITS + "d", value);
    }

    public static String hash(String rawCode) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hashed = digest.digest(rawCode.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(hashed);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 is not available", e);
        }
    }

    /** Constant-time comparison of two hashes, to avoid a timing side channel. */
    public static boolean hashesMatch(String a, String b) {
        return MessageDigest.isEqual(
                a.getBytes(StandardCharsets.UTF_8), b.getBytes(StandardCharsets.UTF_8));
    }
}
