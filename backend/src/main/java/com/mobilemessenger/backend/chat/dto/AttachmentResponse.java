package com.mobilemessenger.backend.chat.dto;

import com.mobilemessenger.backend.chat.MessageAttachment;
import java.util.UUID;

public record AttachmentResponse(
        UUID id,
        String type,
        String mimeType,
        long fileSize,
        Integer width,
        Integer height,
        Integer durationSeconds,
        String url,
        String thumbnailUrl) {

    public static AttachmentResponse from(MessageAttachment attachment) {
        UUID id = attachment.getId();
        return new AttachmentResponse(
                id,
                attachment.getType().name(),
                attachment.getMimeType(),
                attachment.getFileSize(),
                attachment.getWidth(),
                attachment.getHeight(),
                attachment.getDurationSeconds(),
                "/api/attachments/" + id,
                attachment.getThumbnailStorageKey() != null ? "/api/attachments/" + id + "/thumbnail" : null);
    }
}
