package com.mobilemessenger.backend.chat;

import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpRange;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Authenticated, participant-scoped attachment access. Never exposes the
 * physical storage path - only an opaque {@code attachmentId}, authorized
 * via {@link AttachmentService#requireAccessible} on every request (the
 * storage key itself is never treated as proof of authorization).
 */
@RestController
@RequestMapping("/api/attachments")
public class AttachmentController {

    private final AttachmentService attachmentService;

    public AttachmentController(AttachmentService attachmentService) {
        this.attachmentService = attachmentService;
    }

    /**
     * Serves the original file, supporting HTTP range requests so a video
     * player can seek without downloading the whole file.
     *
     * <p>Stored files are encrypted at rest (see {@link
     * com.mobilemessenger.backend.storage.LocalFileStorageService}), which
     * rules out Spring's usual {@code ResourceRegion} streaming (it assumes
     * a plaintext-seekable resource). Instead {@link
     * AttachmentService#loadRange} decrypts only the chunks overlapping the
     * requested byte range directly from disk, so a range request into a
     * large video still never decrypts - or reads - the whole file, even
     * though the response body here is a single decrypted byte array for
     * just that range (never the whole file).
     */
    @GetMapping("/{attachmentId}")
    public ResponseEntity<byte[]> download(
            Authentication authentication,
            @PathVariable UUID attachmentId,
            @RequestHeader(value = HttpHeaders.RANGE, required = false) String rangeHeader) {
        MessageAttachment attachment = attachmentService.requireAccessible(attachmentId, currentUserId(authentication));
        long contentLength = attachmentService.sizeOf(attachment);

        List<HttpRange> ranges = rangeHeader == null ? List.of() : HttpRange.parseRanges(rangeHeader);
        boolean isPartial = !ranges.isEmpty();
        long start = 0;
        long end = contentLength - 1;
        if (isPartial) {
            HttpRange range = ranges.get(0);
            start = range.getRangeStart(contentLength);
            end = range.getRangeEnd(contentLength);
        }

        byte[] body = attachmentService.loadRange(attachment, start, end);

        ResponseEntity.BodyBuilder response = ResponseEntity.status(isPartial ? HttpStatus.PARTIAL_CONTENT : HttpStatus.OK)
                .header(HttpHeaders.CONTENT_TYPE, attachment.getMimeType())
                .header(HttpHeaders.ACCEPT_RANGES, "bytes")
                .header(HttpHeaders.CACHE_CONTROL, "private, max-age=86400")
                .header(HttpHeaders.CONTENT_LENGTH, String.valueOf(body.length));
        if (isPartial) {
            response.header(HttpHeaders.CONTENT_RANGE, "bytes " + start + "-" + end + "/" + contentLength);
        }
        return response.body(body);
    }

    @GetMapping("/{attachmentId}/thumbnail")
    public ResponseEntity<byte[]> thumbnail(Authentication authentication, @PathVariable UUID attachmentId) {
        MessageAttachment attachment = attachmentService.requireAccessible(attachmentId, currentUserId(authentication));
        byte[] thumbnail = attachmentService.loadThumbnail(attachment);
        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_TYPE, MediaType.IMAGE_JPEG_VALUE)
                .header(HttpHeaders.CACHE_CONTROL, "private, max-age=86400")
                .body(thumbnail);
    }

    private UUID currentUserId(Authentication authentication) {
        return (UUID) authentication.getPrincipal();
    }
}
