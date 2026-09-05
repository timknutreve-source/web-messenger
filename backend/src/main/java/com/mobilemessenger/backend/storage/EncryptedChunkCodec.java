package com.mobilemessenger.backend.storage;

import com.mobilemessenger.backend.security.encryption.EncryptionService;
import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;

/**
 * On-disk container format used by {@link LocalFileStorageService} to store
 * uploaded file bytes (images, videos, thumbnails, avatars) encrypted at
 * rest, while still supporting random-access reads for a specific byte
 * range - required to keep HTTP range requests (video seeking) working
 * without ever decrypting - or even reading - a whole large file into
 * memory just to serve a small slice of it.
 *
 * <p>A single AES-GCM operation authenticates its entire input as one unit,
 * so it can't be decrypted starting from the middle. Splitting the
 * plaintext into fixed-size chunks and encrypting each one independently
 * (its own random nonce, its own GCM tag) is what makes random access
 * possible: to read plaintext bytes [start, end), only the chunks that
 * overlap that range ever need to be read from disk and decrypted.
 *
 * <p>Container layout:
 * <pre>
 * [4 bytes magic "MMEC"] [4 bytes format version] [8 bytes plaintext length] [4 bytes chunk size]
 * then, back to back: for each chunk i in [0, chunkCount):
 *   the exact envelope returned by {@link EncryptionService#encryptBytes} for that
 *   chunk's plaintext - this class never inspects or reconstructs that envelope's
 *   internal layout, it only knows its fixed on-disk length per chunk.
 * </pre>
 * Every chunk except the last has exactly {@code chunkSize} plaintext bytes,
 * so every chunk except the last occupies exactly {@code chunkSize +
 * ENVELOPE_OVERHEAD} bytes on disk - which is what lets {@link
 * #chunkOffsetOnDisk} compute a chunk's file position directly, without
 * scanning the file. A zero-length file is still one (empty) chunk, so the
 * format never has zero chunks.
 */
final class EncryptedChunkCodec {

    static final int MAGIC = 0x4D4D4543; // "MMEC"
    static final int FORMAT_VERSION = 1;
    static final int DEFAULT_CHUNK_SIZE = 1024 * 1024; // 1 MiB plaintext per chunk

    /** Fixed per-chunk overhead of {@link EncryptionService}'s envelope: 1-byte version + 12-byte nonce + 16-byte GCM tag. */
    static final int ENVELOPE_OVERHEAD = 1 + 12 + 16;
    static final int HEADER_LENGTH = 4 + 4 + 8 + 4; // magic + version + plaintextLength + chunkSize

    private EncryptedChunkCodec() {
    }

    /** Encrypts a whole in-memory plaintext into a complete container, ready to write to disk. */
    static byte[] encryptToContainer(byte[] plaintext, EncryptionService encryptionService) {
        int chunkSize = DEFAULT_CHUNK_SIZE;
        int chunkCount = chunkCount(plaintext.length, chunkSize);

        ByteArrayOutputStream out = new ByteArrayOutputStream(plaintext.length + chunkCount * ENVELOPE_OVERHEAD + HEADER_LENGTH);
        out.writeBytes(header(plaintext.length, chunkSize));

        for (int i = 0; i < chunkCount; i++) {
            int start = i * chunkSize;
            int end = Math.min(start + chunkSize, plaintext.length);
            byte[] plainChunk = new byte[end - start];
            System.arraycopy(plaintext, start, plainChunk, 0, plainChunk.length);
            out.writeBytes(encryptionService.encryptBytes(plainChunk));
        }
        return out.toByteArray();
    }

    /** Decrypts an entire container's bytes back to the full plaintext. Only safe for small files (thumbnails, avatars). */
    static byte[] decryptContainer(byte[] container, EncryptionService encryptionService) {
        Header header = readHeader(container);
        return decryptRange(container, header, 0, header.plaintextLength - 1, encryptionService);
    }

    /** Decrypts only the chunks overlapping [startInclusive, endInclusive] of the plaintext, from an in-memory container. */
    static byte[] decryptRange(byte[] container, long startInclusive, long endInclusive, EncryptionService encryptionService) {
        return decryptRange(container, readHeader(container), startInclusive, endInclusive, encryptionService);
    }

    private static byte[] decryptRange(byte[] container, Header header, long startInclusive, long endInclusive, EncryptionService encryptionService) {
        if (header.plaintextLength == 0) {
            return new byte[0];
        }
        long clampedStart = Math.max(0, startInclusive);
        long clampedEnd = Math.min(endInclusive, header.plaintextLength - 1);
        if (clampedEnd < clampedStart) {
            return new byte[0];
        }

        int firstChunk = (int) (clampedStart / header.chunkSize);
        int lastChunk = (int) (clampedEnd / header.chunkSize);

        ByteArrayOutputStream out = new ByteArrayOutputStream((int) (clampedEnd - clampedStart + 1));
        for (int i = firstChunk; i <= lastChunk; i++) {
            int diskOffset = chunkOffsetOnDisk(i, header.chunkSize);
            int diskLength = chunkDiskLength(i, header.plaintextLength, header.chunkSize);
            byte[] chunkOnDisk = new byte[diskLength];
            System.arraycopy(container, diskOffset, chunkOnDisk, 0, diskLength);
            byte[] plainChunk = encryptionService.decryptBytes(chunkOnDisk);

            long chunkStart = (long) i * header.chunkSize;
            int sliceFrom = (int) Math.max(0, clampedStart - chunkStart);
            int sliceTo = (int) Math.min(plainChunk.length, clampedEnd - chunkStart + 1);
            out.write(plainChunk, sliceFrom, sliceTo - sliceFrom);
        }
        return out.toByteArray();
    }

    static Header readHeader(byte[] container) {
        if (container.length < HEADER_LENGTH) {
            throw new IllegalArgumentException("Encrypted container is truncated (missing header)");
        }
        ByteBuffer buf = ByteBuffer.wrap(container, 0, HEADER_LENGTH);
        int magic = buf.getInt();
        int version = buf.getInt();
        long plaintextLength = buf.getLong();
        int chunkSize = buf.getInt();
        if (magic != MAGIC) {
            throw new IllegalArgumentException("Not a recognized encrypted file container");
        }
        if (version != FORMAT_VERSION) {
            throw new IllegalArgumentException("Unsupported encrypted file container version: " + version);
        }
        return new Header(plaintextLength, chunkSize);
    }

    static int chunkOffsetOnDisk(int chunkIndex, int chunkSize) {
        return HEADER_LENGTH + chunkIndex * fixedChunkDiskSize(chunkSize);
    }

    static int chunkDiskLength(int chunkIndex, long plaintextLength, int chunkSize) {
        int chunkCount = chunkCount(plaintextLength, chunkSize);
        if (chunkIndex < chunkCount - 1) {
            return fixedChunkDiskSize(chunkSize);
        }
        long lastChunkPlainLength = plaintextLength - (long) (chunkCount - 1) * chunkSize;
        return ENVELOPE_OVERHEAD + (int) lastChunkPlainLength;
    }

    private static int fixedChunkDiskSize(int chunkSize) {
        return ENVELOPE_OVERHEAD + chunkSize;
    }

    static int chunkCount(long plaintextLength, int chunkSize) {
        return (int) Math.max(1, (plaintextLength + chunkSize - 1) / chunkSize);
    }

    private static byte[] header(long plaintextLength, int chunkSize) {
        return ByteBuffer.allocate(HEADER_LENGTH)
                .putInt(MAGIC)
                .putInt(FORMAT_VERSION)
                .putLong(plaintextLength)
                .putInt(chunkSize)
                .array();
    }

    record Header(long plaintextLength, int chunkSize) {
    }
}
