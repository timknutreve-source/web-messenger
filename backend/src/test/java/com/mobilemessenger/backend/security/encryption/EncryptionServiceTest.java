package com.mobilemessenger.backend.security.encryption;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import com.mobilemessenger.backend.security.encryption.exception.DecryptionException;
import java.security.SecureRandom;
import java.util.Base64;
import org.junit.jupiter.api.Test;

/**
 * Pure unit tests for {@link EncryptionService}: no Spring context, no
 * database - just the AES-256-GCM envelope contract itself.
 */
class EncryptionServiceTest {

    private static final String KEY_A = randomBase64Key();
    private static final String KEY_B = randomBase64Key();

    private final EncryptionService service = new EncryptionService(KEY_A);

    @Test
    void roundTripsPlainAsciiText() {
        String plaintext = "hello, world";
        assertEquals(plaintext, service.decrypt(service.encrypt(plaintext)));
    }

    @Test
    void roundTripsEmptyString() {
        assertEquals("", service.decrypt(service.encrypt("")));
    }

    @Test
    void roundTripsUnicodeText() {
        String plaintext = "héllo 世界 🎉🔒 café naïve";
        assertEquals(plaintext, service.decrypt(service.encrypt(plaintext)));
    }

    @Test
    void roundTripsLongText() {
        String plaintext = "A".repeat(20_000) + "z";
        assertEquals(plaintext, service.decrypt(service.encrypt(plaintext)));
    }

    @Test
    void roundTripsBinaryData() {
        byte[] plaintext = new byte[10_000];
        new SecureRandom().nextBytes(plaintext);
        assertArrayEquals(plaintext, service.decryptBytes(service.encryptBytes(plaintext)));
    }

    @Test
    void roundTripsEmptyByteArray() {
        assertArrayEquals(new byte[0], service.decryptBytes(service.encryptBytes(new byte[0])));
    }

    @Test
    void sameInputProducesDifferentCiphertextEachTime() {
        String plaintext = "same message every time";
        String first = service.encrypt(plaintext);
        String second = service.encrypt(plaintext);
        assertNotEquals(first, second, "ciphertext must differ due to a random nonce, even for identical plaintext");
        // But both still decrypt back to the same plaintext.
        assertEquals(plaintext, service.decrypt(first));
        assertEquals(plaintext, service.decrypt(second));
    }

    @Test
    void tamperedCiphertextFailsToDecrypt() {
        String encoded = service.encrypt("do not tamper with me");
        byte[] envelope = Base64.getDecoder().decode(encoded);
        envelope[envelope.length - 1] ^= 0x01; // flip a bit inside the GCM tag
        String tampered = Base64.getEncoder().encodeToString(envelope);

        assertThrows(DecryptionException.class, () -> service.decrypt(tampered));
    }

    @Test
    void truncatedCiphertextFailsToDecrypt() {
        String encoded = service.encrypt("some message");
        byte[] envelope = Base64.getDecoder().decode(encoded);
        byte[] truncated = new byte[envelope.length - 5];
        System.arraycopy(envelope, 0, truncated, 0, truncated.length);
        String truncatedEncoded = Base64.getEncoder().encodeToString(truncated);

        assertThrows(DecryptionException.class, () -> service.decrypt(truncatedEncoded));
    }

    @Test
    void invalidBase64FailsToDecrypt() {
        assertThrows(DecryptionException.class, () -> service.decrypt("not valid base64!!! ###"));
    }

    @Test
    void garbageButValidBase64FailsToDecrypt() {
        String garbage = Base64.getEncoder().encodeToString("this is not an envelope at all".getBytes());
        assertThrows(DecryptionException.class, () -> service.decrypt(garbage));
    }

    @Test
    void wrongKeyFailsToDecrypt() {
        String encoded = service.encrypt("secret for key A only");
        EncryptionService otherService = new EncryptionService(KEY_B);
        assertThrows(DecryptionException.class, () -> otherService.decrypt(encoded));
    }

    @Test
    void nullKeyIsRejectedAtConstruction() {
        assertThrows(IllegalStateException.class, () -> new EncryptionService(null));
    }

    @Test
    void blankKeyIsRejectedAtConstruction() {
        assertThrows(IllegalStateException.class, () -> new EncryptionService("   "));
    }

    @Test
    void nonBase64KeyIsRejectedAtConstruction() {
        assertThrows(IllegalStateException.class, () -> new EncryptionService("not base64!!!"));
    }

    @Test
    void wrongLengthKeyIsRejectedAtConstruction_tooShort() {
        String shortKey = Base64.getEncoder().encodeToString(new byte[16]); // 128 bits, not 256
        assertThrows(IllegalStateException.class, () -> new EncryptionService(shortKey));
    }

    @Test
    void wrongLengthKeyIsRejectedAtConstruction_tooLong() {
        String longKey = Base64.getEncoder().encodeToString(new byte[64]); // 512 bits, not 256
        assertThrows(IllegalStateException.class, () -> new EncryptionService(longKey));
    }

    @Test
    void keyIsNeverSilentlyTruncatedOrPadded() {
        // A 31-byte key must be rejected outright, not padded up to 32.
        String almostRightKey = Base64.getEncoder().encodeToString(new byte[31]);
        assertThrows(IllegalStateException.class, () -> new EncryptionService(almostRightKey));
    }

    private static String randomBase64Key() {
        byte[] key = new byte[32];
        new SecureRandom().nextBytes(key);
        return Base64.getEncoder().encodeToString(key);
    }
}
