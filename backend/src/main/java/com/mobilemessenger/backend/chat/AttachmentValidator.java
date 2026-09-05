package com.mobilemessenger.backend.chat;

import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import javax.imageio.ImageIO;

/**
 * Detects the real type of an uploaded attachment by sniffing its content
 * (magic bytes), never trusting the client-supplied file name or {@code
 * Content-Type} header - both are trivially spoofed. Also does what it can
 * with the same already-decoded bytes: image dimensions and a resized
 * thumbnail (both via {@code javax.imageio}, no extra dependency).
 *
 * <p>WebP images are recognized and accepted, but the JDK's built-in
 * ImageIO has no WebP reader, so {@link #detect} still returns a positive
 * result for them while dimensions/thumbnail generation are silently
 * skipped (left {@code null}) - see the README's "known limitations".
 */
public final class AttachmentValidator {

    /** Longest side of a generated image thumbnail, in pixels. */
    private static final int THUMBNAIL_MAX_DIMENSION = 480;

    private AttachmentValidator() {
    }

    public record Detected(AttachmentType type, String mimeType, String extension) {
    }

    /** Returns the detected attachment type, or {@code null} if the content isn't a supported format. */
    public static Detected detect(byte[] content) {
        if (startsWith(content, JPEG_MAGIC)) {
            return new Detected(AttachmentType.IMAGE, "image/jpeg", "jpg");
        }
        if (startsWith(content, PNG_MAGIC)) {
            return new Detected(AttachmentType.IMAGE, "image/png", "png");
        }
        if (isWebp(content)) {
            return new Detected(AttachmentType.IMAGE, "image/webp", "webp");
        }
        if (isWebm(content)) {
            return new Detected(AttachmentType.VIDEO, "video/webm", "webm");
        }
        String isoBrand = isoBaseMediaBrand(content);
        if ("qt  ".equals(isoBrand)) {
            return new Detected(AttachmentType.VIDEO, "video/quicktime", "mov");
        }
        if (isoBrand != null) {
            return new Detected(AttachmentType.VIDEO, "video/mp4", "mp4");
        }
        return null;
    }

    /** Best-effort image dimensions; {@code null} for formats ImageIO can't decode (e.g. WebP). */
    public static int[] readImageDimensions(byte[] content) {
        try {
            BufferedImage image = ImageIO.read(new ByteArrayInputStream(content));
            return image == null ? null : new int[] {image.getWidth(), image.getHeight()};
        } catch (IOException e) {
            return null;
        }
    }

    /**
     * A downscaled JPEG thumbnail (longest side capped at {@value
     * #THUMBNAIL_MAX_DIMENSION}px), or {@code null} if the source can't be
     * decoded or is already smaller than the cap.
     */
    public static byte[] generateThumbnail(byte[] content) {
        try {
            BufferedImage source = ImageIO.read(new ByteArrayInputStream(content));
            if (source == null) {
                return null;
            }
            int width = source.getWidth();
            int height = source.getHeight();
            if (Math.max(width, height) <= THUMBNAIL_MAX_DIMENSION) {
                return null;
            }

            double scale = THUMBNAIL_MAX_DIMENSION / (double) Math.max(width, height);
            int targetWidth = Math.max(1, (int) Math.round(width * scale));
            int targetHeight = Math.max(1, (int) Math.round(height * scale));

            BufferedImage thumbnail = new BufferedImage(targetWidth, targetHeight, BufferedImage.TYPE_INT_RGB);
            Graphics2D graphics = thumbnail.createGraphics();
            try {
                graphics.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR);
                graphics.drawImage(source, 0, 0, targetWidth, targetHeight, null);
            } finally {
                graphics.dispose();
            }

            ByteArrayOutputStream out = new ByteArrayOutputStream();
            ImageIO.write(thumbnail, "jpg", out);
            return out.toByteArray();
        } catch (IOException e) {
            return null;
        }
    }

    private static final byte[] JPEG_MAGIC = {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF};
    private static final byte[] PNG_MAGIC = {
        (byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
    };
    private static final byte[] EBML_MAGIC = {(byte) 0x1A, (byte) 0x45, (byte) 0xDF, (byte) 0xA3};

    private static boolean isWebp(byte[] content) {
        return content.length >= 12
                && matchesAscii(content, 0, "RIFF")
                && matchesAscii(content, 8, "WEBP");
    }

    private static boolean isWebm(byte[] content) {
        return startsWith(content, EBML_MAGIC);
    }

    /** ISO base media file format (mp4/mov/...): a 4-byte size, then "ftyp", then a 4-byte brand. */
    private static String isoBaseMediaBrand(byte[] content) {
        if (content.length < 12 || !matchesAscii(content, 4, "ftyp")) {
            return null;
        }
        return new String(content, 8, 4, java.nio.charset.StandardCharsets.US_ASCII);
    }

    private static boolean matchesAscii(byte[] content, int offset, String ascii) {
        byte[] expected = ascii.getBytes(java.nio.charset.StandardCharsets.US_ASCII);
        return startsWithAt(content, offset, expected);
    }

    private static boolean startsWith(byte[] content, byte[] prefix) {
        return startsWithAt(content, 0, prefix);
    }

    private static boolean startsWithAt(byte[] content, int offset, byte[] expected) {
        if (content.length < offset + expected.length) {
            return false;
        }
        for (int i = 0; i < expected.length; i++) {
            if (content[offset + i] != expected[i]) {
                return false;
            }
        }
        return true;
    }
}
