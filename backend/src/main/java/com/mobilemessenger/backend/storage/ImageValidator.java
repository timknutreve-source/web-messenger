package com.mobilemessenger.backend.storage;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.util.Iterator;
import java.util.Locale;
import java.util.Set;
import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.ImageInputStream;

/**
 * Validates that uploaded bytes are genuinely a supported image format, by
 * sniffing the actual file content rather than trusting the client-supplied
 * file name or {@code Content-Type} header (both are easily spoofed).
 */
public final class ImageValidator {

    public static final long MAX_AVATAR_SIZE_BYTES = 5L * 1024 * 1024;

    private static final Set<String> ALLOWED_FORMATS = Set.of("jpeg", "png");

    private ImageValidator() {
    }

    /**
     * Returns the detected image format ({@code "jpeg"} or {@code "png"}),
     * or {@code null} if the content is not readable as an image or is not
     * one of the supported formats.
     */
    public static String detectSupportedFormat(byte[] content) {
        try (ImageInputStream iis = ImageIO.createImageInputStream(new ByteArrayInputStream(content))) {
            if (iis == null) {
                return null;
            }
            Iterator<ImageReader> readers = ImageIO.getImageReaders(iis);
            if (!readers.hasNext()) {
                return null;
            }
            String formatName = readers.next().getFormatName().toLowerCase(Locale.ROOT);
            return ALLOWED_FORMATS.contains(formatName) ? formatName : null;
        } catch (IOException e) {
            return null;
        }
    }
}
