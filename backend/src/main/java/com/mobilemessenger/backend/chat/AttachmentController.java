package com.mobilemessenger.backend.chat;

import java.util.List;
import java.util.UUID;
import org.springframework.core.io.Resource;
import org.springframework.core.io.support.ResourceRegion;
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
     * player can seek without downloading the whole file - the response
     * streams directly from storage rather than buffering it in memory.
     */
    @GetMapping("/{attachmentId}")
    public ResponseEntity<ResourceRegion> download(
            Authentication authentication,
            @PathVariable UUID attachmentId,
            @RequestHeader(value = HttpHeaders.RANGE, required = false) String rangeHeader) {
        MessageAttachment attachment = attachmentService.requireAccessible(attachmentId, currentUserId(authentication));
        Resource resource = attachmentService.loadResource(attachment);
        long contentLength = attachmentService.sizeOf(attachment);

        List<HttpRange> ranges = rangeHeader == null ? List.of() : HttpRange.parseRanges(rangeHeader);
        ResourceRegion region = ranges.isEmpty()
                ? new ResourceRegion(resource, 0, contentLength)
                : ranges.get(0).toResourceRegion(resource);

        return ResponseEntity.status(ranges.isEmpty() ? HttpStatus.OK : HttpStatus.PARTIAL_CONTENT)
                .header(HttpHeaders.CONTENT_TYPE, attachment.getMimeType())
                .header(HttpHeaders.ACCEPT_RANGES, "bytes")
                .header(HttpHeaders.CACHE_CONTROL, "private, max-age=86400")
                .body(region);
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
