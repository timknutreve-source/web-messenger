package com.mobilemessenger.backend.storage;

import com.mobilemessenger.backend.security.encryption.EncryptionService;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.ByteBuffer;
import java.nio.channels.SeekableByteChannel;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * Stores files on the local filesystem under a configurable root directory
 * (see {@code storage.root-dir}). In Docker this directory is backed by a
 * named volume so uploads survive container recreation.
 *
 * <p>Every file is encrypted at rest using {@link EncryptedChunkCodec}'s
 * chunked AES-256-GCM container format - the plaintext is never written to
 * disk. {@link #loadRange} reads the on-disk container with random access
 * (via a {@link SeekableByteChannel}), seeking directly to and decrypting
 * only the chunks that overlap the requested byte range, so serving a byte
 * range from a large video never requires reading or decrypting the whole
 * file - see {@link com.mobilemessenger.backend.chat.AttachmentController}.
 */
@Service
public class LocalFileStorageService implements FileStorageService {

    private final Path rootDir;
    private final EncryptionService encryptionService;

    public LocalFileStorageService(@Value("${storage.root-dir}") String rootDir, EncryptionService encryptionService) {
        this.rootDir = Path.of(rootDir).toAbsolutePath().normalize();
        this.encryptionService = encryptionService;
    }

    @Override
    public String store(String category, byte[] content, String fileExtension) {
        String storedFileName = UUID.randomUUID() + "." + fileExtension;
        Path target = resolveSafe(category, storedFileName);
        byte[] container = EncryptedChunkCodec.encryptToContainer(content, encryptionService);
        try {
            Files.createDirectories(target.getParent());
            Files.write(target, container);
        } catch (IOException e) {
            throw new UncheckedIOException("Failed to store file", e);
        }
        return storedFileName;
    }

    @Override
    public byte[] load(String category, String storedFileName) {
        byte[] container;
        try {
            container = Files.readAllBytes(resolveSafe(category, storedFileName));
        } catch (IOException e) {
            throw new UncheckedIOException("Failed to read stored file", e);
        }
        return EncryptedChunkCodec.decryptContainer(container, encryptionService);
    }

    @Override
    public byte[] loadRange(String category, String storedFileName, long startInclusive, long endInclusive) {
        Path path = resolveSafe(category, storedFileName);
        try (SeekableByteChannel channel = Files.newByteChannel(path, StandardOpenOption.READ)) {
            ByteBuffer headerBuffer = ByteBuffer.allocate(EncryptedChunkCodec.HEADER_LENGTH);
            readFully(channel, headerBuffer);
            EncryptedChunkCodec.Header header = EncryptedChunkCodec.readHeader(headerBuffer.array());

            if (header.plaintextLength() == 0) {
                return new byte[0];
            }
            long clampedStart = Math.max(0, startInclusive);
            long clampedEnd = Math.min(endInclusive, header.plaintextLength() - 1);
            if (clampedEnd < clampedStart) {
                return new byte[0];
            }

            int chunkSize = header.chunkSize();
            int firstChunk = (int) (clampedStart / chunkSize);
            int lastChunk = (int) (clampedEnd / chunkSize);

            java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream((int) (clampedEnd - clampedStart + 1));
            for (int i = firstChunk; i <= lastChunk; i++) {
                int diskOffset = EncryptedChunkCodec.chunkOffsetOnDisk(i, chunkSize);
                int diskLength = EncryptedChunkCodec.chunkDiskLength(i, header.plaintextLength(), chunkSize);

                ByteBuffer chunkBuffer = ByteBuffer.allocate(diskLength);
                channel.position(diskOffset);
                readFully(channel, chunkBuffer);
                byte[] plainChunk = encryptionService.decryptBytes(chunkBuffer.array());

                long chunkStart = (long) i * chunkSize;
                int sliceFrom = (int) Math.max(0, clampedStart - chunkStart);
                int sliceTo = (int) Math.min(plainChunk.length, clampedEnd - chunkStart + 1);
                out.write(plainChunk, sliceFrom, sliceTo - sliceFrom);
            }
            return out.toByteArray();
        } catch (IOException e) {
            throw new UncheckedIOException("Failed to read stored file", e);
        }
    }

    private static void readFully(SeekableByteChannel channel, ByteBuffer buffer) throws IOException {
        while (buffer.hasRemaining()) {
            if (channel.read(buffer) < 0) {
                throw new IOException("Unexpected end of file while reading encrypted container");
            }
        }
        buffer.flip();
    }

    @Override
    public boolean exists(String category, String storedFileName) {
        return Files.exists(resolveSafe(category, storedFileName));
    }

    @Override
    public void delete(String category, String storedFileName) {
        try {
            Files.deleteIfExists(resolveSafe(category, storedFileName));
        } catch (IOException e) {
            throw new UncheckedIOException("Failed to delete stored file", e);
        }
    }

    @Override
    public long size(String category, String storedFileName) {
        Path path = resolveSafe(category, storedFileName);
        try (SeekableByteChannel channel = Files.newByteChannel(path, StandardOpenOption.READ)) {
            ByteBuffer headerBuffer = ByteBuffer.allocate(EncryptedChunkCodec.HEADER_LENGTH);
            readFully(channel, headerBuffer);
            return EncryptedChunkCodec.readHeader(headerBuffer.array()).plaintextLength();
        } catch (IOException e) {
            throw new UncheckedIOException("Failed to read stored file size", e);
        }
    }

    /**
     * Resolves a category + stored file name to a path guaranteed to stay
     * inside {@link #rootDir}, rejecting any attempt at path traversal.
     */
    private Path resolveSafe(String category, String storedFileName) {
        if (storedFileName == null
                || storedFileName.isBlank()
                || storedFileName.contains("/")
                || storedFileName.contains("\\")
                || storedFileName.contains("..")) {
            throw new IllegalArgumentException("Invalid stored file name");
        }
        Path resolved = rootDir.resolve(category).resolve(storedFileName).normalize();
        if (!resolved.startsWith(rootDir)) {
            throw new IllegalArgumentException("Invalid stored file name");
        }
        return resolved;
    }
}
