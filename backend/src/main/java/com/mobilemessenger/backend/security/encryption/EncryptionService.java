package com.mobilemessenger.backend.security.encryption;

import com.mobilemessenger.backend.security.encryption.exception.DecryptionException;
import com.mobilemessenger.backend.security.encryption.exception.EncryptionException;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.Base64;
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * Application-level AES-256-GCM encryption for data at rest (message text,
 * profile fields, and - via {@link com.mobilemessenger.backend.storage.LocalFileStorageService} -
 * uploaded media bytes).
 *
 * <p>Every encrypted value is a self-describing envelope:
 * {@code [1 byte version][12 byte nonce][ciphertext || 16 byte GCM tag]}.
 * The version byte lets the format evolve later without breaking existing
 * data; the nonce is generated fresh with {@link SecureRandom} for every
 * call, so the same plaintext never produces the same ciphertext twice and
 * a nonce is never reused under the same key. The GCM tag authenticates the
 * ciphertext - any bit flip, truncation, or wrong-key attempt fails {@link
 * #decrypt}/{@link #decryptBytes} with a {@link DecryptionException} rather
 * than silently returning garbage.
 *
 * <p>The key comes from {@code app.encryption.master-key} (env var {@code
 * ENCRYPTION_MASTER_KEY}), which must be a Base64-encoded 256-bit (32-byte)
 * value - see application.properties. The key is decoded once, validated
 * for exact length (never silently truncated or padded), and held only as
 * an in-memory {@link SecretKeySpec}; it is never logged and this class
 * never logs plaintext.
 */
@Service
public class EncryptionService {

    private static final String TRANSFORMATION = "AES/GCM/NoPadding";
    private static final int GCM_TAG_LENGTH_BITS = 128;
    private static final int NONCE_LENGTH_BYTES = 12;
    private static final byte ENVELOPE_VERSION = 1;
    private static final int MIN_ENVELOPE_LENGTH = 1 + NONCE_LENGTH_BYTES + (GCM_TAG_LENGTH_BITS / 8);

    private final SecretKeySpec key;
    private final SecureRandom secureRandom = new SecureRandom();

    public EncryptionService(@Value("${app.encryption.master-key}") String base64Key) {
        this.key = new SecretKeySpec(decodeKey(base64Key), "AES");
    }

    private static byte[] decodeKey(String base64Key) {
        if (base64Key == null || base64Key.isBlank()) {
            throw new IllegalStateException(
                    "app.encryption.master-key (ENCRYPTION_MASTER_KEY) is not set. Generate one with: "
                            + "openssl rand -base64 32");
        }
        byte[] keyBytes;
        try {
            keyBytes = Base64.getDecoder().decode(base64Key.trim());
        } catch (IllegalArgumentException e) {
            throw new IllegalStateException(
                    "app.encryption.master-key (ENCRYPTION_MASTER_KEY) must be valid Base64", e);
        }
        if (keyBytes.length != 32) {
            throw new IllegalStateException(
                    "app.encryption.master-key (ENCRYPTION_MASTER_KEY) must decode to exactly 32 bytes "
                            + "(256 bits) for AES-256; got " + keyBytes.length
                            + " bytes. Generate one with: openssl rand -base64 32");
        }
        return keyBytes;
    }

    /** Encrypts UTF-8 text, returning a Base64-encoded envelope safe to store in a text column. */
    public String encrypt(String plaintext) {
        if (plaintext == null) {
            throw new EncryptionException("Cannot encrypt a null value");
        }
        return Base64.getEncoder().encodeToString(encryptRaw(plaintext.getBytes(StandardCharsets.UTF_8)));
    }

    /** Reverses {@link #encrypt}. Throws {@link DecryptionException} on any malformed or tampered input. */
    public String decrypt(String encoded) {
        if (encoded == null) {
            throw new DecryptionException("Cannot decrypt a null value");
        }
        byte[] envelope;
        try {
            envelope = Base64.getDecoder().decode(encoded);
        } catch (IllegalArgumentException e) {
            throw new DecryptionException("Ciphertext is not valid Base64", e);
        }
        return new String(decryptRaw(envelope), StandardCharsets.UTF_8);
    }

    /** Encrypts arbitrary bytes, returning the raw envelope (no Base64) - used for binary payloads such as file chunks. */
    public byte[] encryptBytes(byte[] plaintext) {
        if (plaintext == null) {
            throw new EncryptionException("Cannot encrypt a null value");
        }
        return encryptRaw(plaintext);
    }

    /** Reverses {@link #encryptBytes}. Throws {@link DecryptionException} on any malformed or tampered input. */
    public byte[] decryptBytes(byte[] envelope) {
        if (envelope == null) {
            throw new DecryptionException("Cannot decrypt a null value");
        }
        return decryptRaw(envelope);
    }

    private byte[] encryptRaw(byte[] plaintext) {
        byte[] nonce = new byte[NONCE_LENGTH_BYTES];
        secureRandom.nextBytes(nonce);
        try {
            Cipher cipher = Cipher.getInstance(TRANSFORMATION);
            cipher.init(Cipher.ENCRYPT_MODE, key, new GCMParameterSpec(GCM_TAG_LENGTH_BITS, nonce));
            byte[] ciphertext = cipher.doFinal(plaintext);

            byte[] envelope = new byte[1 + NONCE_LENGTH_BYTES + ciphertext.length];
            envelope[0] = ENVELOPE_VERSION;
            System.arraycopy(nonce, 0, envelope, 1, NONCE_LENGTH_BYTES);
            System.arraycopy(ciphertext, 0, envelope, 1 + NONCE_LENGTH_BYTES, ciphertext.length);
            return envelope;
        } catch (GeneralSecurityException e) {
            throw new EncryptionException("Encryption failed", e);
        }
    }

    private byte[] decryptRaw(byte[] envelope) {
        if (envelope.length < MIN_ENVELOPE_LENGTH) {
            throw new DecryptionException("Ciphertext is too short to be valid");
        }
        if (envelope[0] != ENVELOPE_VERSION) {
            throw new DecryptionException("Unsupported ciphertext envelope version");
        }
        byte[] nonce = new byte[NONCE_LENGTH_BYTES];
        System.arraycopy(envelope, 1, nonce, 0, NONCE_LENGTH_BYTES);
        int ciphertextOffset = 1 + NONCE_LENGTH_BYTES;
        int ciphertextLength = envelope.length - ciphertextOffset;

        try {
            Cipher cipher = Cipher.getInstance(TRANSFORMATION);
            cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(GCM_TAG_LENGTH_BITS, nonce));
            return cipher.doFinal(envelope, ciphertextOffset, ciphertextLength);
        } catch (GeneralSecurityException e) {
            // Covers both a wrong key and tampered/corrupted ciphertext - AES-GCM
            // deliberately makes these indistinguishable to the caller.
            throw new DecryptionException("Ciphertext could not be authenticated (wrong key or tampered data)", e);
        }
    }
}
