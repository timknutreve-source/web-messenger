package com.mobilemessenger.backend.storage;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import com.mobilemessenger.backend.security.encryption.EncryptionService;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.Base64;
import org.junit.jupiter.api.Test;

/**
 * Unit tests for the encrypted file container format, in particular that
 * {@link EncryptedChunkCodec#decryptRange} returns exactly the requested
 * byte range regardless of how it falls across chunk boundaries - this is
 * what backs range-request (video seek) support in {@link
 * LocalFileStorageService#loadRange}.
 */
class EncryptedChunkCodecTest {

    private final EncryptionService encryptionService = new EncryptionService(randomBase64Key());

    @Test
    void roundTripsSmallContentSmallerThanOneChunk() {
        byte[] plaintext = "hello world, this is a small file".getBytes();
        byte[] container = EncryptedChunkCodec.encryptToContainer(plaintext, encryptionService);
        assertArrayEquals(plaintext, EncryptedChunkCodec.decryptContainer(container, encryptionService));
    }

    @Test
    void roundTripsEmptyContent() {
        byte[] container = EncryptedChunkCodec.encryptToContainer(new byte[0], encryptionService);
        assertArrayEquals(new byte[0], EncryptedChunkCodec.decryptContainer(container, encryptionService));
    }

    @Test
    void roundTripsContentSpanningMultipleChunks() {
        byte[] plaintext = randomBytes(3_500_000); // spans several 1 MiB chunks, with a partial final chunk
        byte[] container = EncryptedChunkCodec.encryptToContainer(plaintext, encryptionService);
        assertArrayEquals(plaintext, EncryptedChunkCodec.decryptContainer(container, encryptionService));
    }

    @Test
    void roundTripsContentExactlyOnAChunkBoundary() {
        byte[] plaintext = randomBytes(EncryptedChunkCodec.DEFAULT_CHUNK_SIZE * 2);
        byte[] container = EncryptedChunkCodec.encryptToContainer(plaintext, encryptionService);
        assertArrayEquals(plaintext, EncryptedChunkCodec.decryptContainer(container, encryptionService));
    }

    @Test
    void decryptRangeReturnsExactSliceWithinASingleChunk() {
        byte[] plaintext = randomBytes(1000);
        byte[] container = EncryptedChunkCodec.encryptToContainer(plaintext, encryptionService);

        byte[] slice = EncryptedChunkCodec.decryptRange(container, 100, 199, encryptionService);
        assertArrayEquals(Arrays.copyOfRange(plaintext, 100, 200), slice);
    }

    @Test
    void decryptRangeReturnsExactSliceSpanningTwoChunks() {
        int chunkSize = EncryptedChunkCodec.DEFAULT_CHUNK_SIZE;
        byte[] plaintext = randomBytes(chunkSize * 2 + 500);
        byte[] container = EncryptedChunkCodec.encryptToContainer(plaintext, encryptionService);

        long start = chunkSize - 50;
        long end = chunkSize + 50;
        byte[] slice = EncryptedChunkCodec.decryptRange(container, start, end, encryptionService);
        assertArrayEquals(Arrays.copyOfRange(plaintext, (int) start, (int) end + 1), slice);
    }

    @Test
    void decryptRangeClampsToActualFileBounds() {
        byte[] plaintext = randomBytes(100);
        byte[] container = EncryptedChunkCodec.encryptToContainer(plaintext, encryptionService);

        byte[] slice = EncryptedChunkCodec.decryptRange(container, 50, 10_000, encryptionService);
        assertArrayEquals(Arrays.copyOfRange(plaintext, 50, 100), slice);
    }

    @Test
    void decryptRangeCoveringWholeFileMatchesFullDecrypt() {
        byte[] plaintext = randomBytes(2_000_000);
        byte[] container = EncryptedChunkCodec.encryptToContainer(plaintext, encryptionService);

        byte[] slice = EncryptedChunkCodec.decryptRange(container, 0, plaintext.length - 1, encryptionService);
        assertArrayEquals(plaintext, slice);
    }

    @Test
    void tamperedChunkFailsToDecrypt() {
        byte[] plaintext = randomBytes(1000);
        byte[] container = EncryptedChunkCodec.encryptToContainer(plaintext, encryptionService);
        container[container.length - 1] ^= 0x01; // flip a bit inside the last chunk's GCM tag

        assertThrows(RuntimeException.class, () -> EncryptedChunkCodec.decryptContainer(container, encryptionService));
    }

    @Test
    void wrongKeyFailsToDecryptContainer() {
        byte[] plaintext = randomBytes(1000);
        byte[] container = EncryptedChunkCodec.encryptToContainer(plaintext, encryptionService);

        EncryptionService otherService = new EncryptionService(randomBase64Key());
        assertThrows(RuntimeException.class, () -> EncryptedChunkCodec.decryptContainer(container, otherService));
    }

    @Test
    void sameContentProducesDifferentContainersEachTime() {
        byte[] plaintext = randomBytes(1000);
        byte[] first = EncryptedChunkCodec.encryptToContainer(plaintext, encryptionService);
        byte[] second = EncryptedChunkCodec.encryptToContainer(plaintext, encryptionService);
        org.junit.jupiter.api.Assertions.assertFalse(Arrays.equals(first, second));
    }

    private static byte[] randomBytes(int length) {
        byte[] bytes = new byte[length];
        new SecureRandom().nextBytes(bytes);
        return bytes;
    }

    private static String randomBase64Key() {
        byte[] key = new byte[32];
        new SecureRandom().nextBytes(key);
        return Base64.getEncoder().encodeToString(key);
    }
}
