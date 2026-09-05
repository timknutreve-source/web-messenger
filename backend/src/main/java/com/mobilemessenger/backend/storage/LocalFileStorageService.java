package com.mobilemessenger.backend.storage;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.stereotype.Service;

/**
 * Stores files on the local filesystem under a configurable root directory
 * (see {@code storage.root-dir}). In Docker this directory is backed by a
 * named volume so uploads survive container recreation.
 */
@Service
public class LocalFileStorageService implements FileStorageService {

    private final Path rootDir;

    public LocalFileStorageService(@Value("${storage.root-dir}") String rootDir) {
        this.rootDir = Path.of(rootDir).toAbsolutePath().normalize();
    }

    @Override
    public String store(String category, byte[] content, String fileExtension) {
        String storedFileName = UUID.randomUUID() + "." + fileExtension;
        Path target = resolveSafe(category, storedFileName);
        try {
            Files.createDirectories(target.getParent());
            Files.write(target, content);
        } catch (IOException e) {
            throw new UncheckedIOException("Failed to store file", e);
        }
        return storedFileName;
    }

    @Override
    public byte[] load(String category, String storedFileName) {
        try {
            return Files.readAllBytes(resolveSafe(category, storedFileName));
        } catch (IOException e) {
            throw new UncheckedIOException("Failed to read stored file", e);
        }
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
    public Resource loadAsResource(String category, String storedFileName) {
        return new FileSystemResource(resolveSafe(category, storedFileName));
    }

    @Override
    public long size(String category, String storedFileName) {
        try {
            return Files.size(resolveSafe(category, storedFileName));
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
