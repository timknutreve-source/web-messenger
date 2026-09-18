package com.mobilemessenger.backend.chat;

import com.mobilemessenger.backend.chat.dto.AttachmentResponse;
import com.mobilemessenger.backend.chat.exception.InvalidAttachmentException;
import com.mobilemessenger.backend.storage.FileStorageService;
import com.mobilemessenger.backend.storage.exception.FileTooLargeException;
import com.mobilemessenger.backend.storage.exception.UnsupportedFileTypeException;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.List;
import java.util.NoSuchElementException;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

/**
 * Uploading and accessing chat image/video attachments. Kept separate from
 * {@link MessageService} since it owns a distinct concern (file validation
 * and storage) - {@code MessageService} only calls {@link
 * #attachPendingToMessage} to consume already-uploaded attachments into a
 * message being sent.
 */
@Service
public class AttachmentService {

    static final String CATEGORY = "chat-attachments";
    static final String THUMBNAIL_CATEGORY = "chat-attachment-thumbnails";

    private final MessageAttachmentRepository attachmentRepository;
    private final ConversationParticipantRepository participantRepository;
    private final MessageRepository messageRepository;
    private final FileStorageService fileStorageService;
    private final long maxImageSizeBytes;
    private final long maxVideoSizeBytes;
    private final long maxAudioSizeBytes;

    /** A voice message longer than this is almost certainly a mistake (e.g. a stuck recording), not real content. */
    private static final int MAX_AUDIO_DURATION_SECONDS = 30 * 60;

    public AttachmentService(
            MessageAttachmentRepository attachmentRepository,
            ConversationParticipantRepository participantRepository,
            MessageRepository messageRepository,
            FileStorageService fileStorageService,
            @Value("${app.attachments.max-image-size-bytes:10485760}") long maxImageSizeBytes,
            @Value("${app.attachments.max-video-size-bytes:52428800}") long maxVideoSizeBytes,
            @Value("${app.attachments.max-audio-size-bytes:15728640}") long maxAudioSizeBytes) {
        this.attachmentRepository = attachmentRepository;
        this.participantRepository = participantRepository;
        this.messageRepository = messageRepository;
        this.fileStorageService = fileStorageService;
        this.maxImageSizeBytes = maxImageSizeBytes;
        this.maxVideoSizeBytes = maxVideoSizeBytes;
        this.maxAudioSizeBytes = maxAudioSizeBytes;
    }

    @Transactional
    public AttachmentResponse upload(UUID conversationId, UUID uploaderId, MultipartFile file) {
        return upload(conversationId, uploaderId, file, null);
    }

    /**
     * {@code durationSeconds} is only meaningful for {@link AttachmentType#AUDIO}
     * (a voice message) - the server never decodes audio to measure it
     * itself (no audio-processing dependency exists in this codebase, same
     * reasoning as video thumbnails not being generated server-side), so
     * the client - which already knows exactly how long it recorded for -
     * reports it. It's ignored for every other attachment type.
     */
    @Transactional
    public AttachmentResponse upload(
            UUID conversationId, UUID uploaderId, MultipartFile file, Integer durationSeconds) {
        requireParticipant(conversationId, uploaderId);

        if (file == null || file.isEmpty()) {
            throw new UnsupportedFileTypeException("No file was uploaded");
        }

        byte[] content;
        try {
            content = file.getBytes();
        } catch (IOException e) {
            throw new UncheckedIOException("Failed to read uploaded file", e);
        }

        AttachmentValidator.Detected detected = AttachmentValidator.detect(content);
        if (detected == null) {
            throw new UnsupportedFileTypeException(
                    "Unsupported file type - only JPEG/PNG/WebP images, MP4/MOV/WebM videos, "
                            + "and WAV audio are supported");
        }

        long maxSize = switch (detected.type()) {
            case IMAGE -> maxImageSizeBytes;
            case VIDEO -> maxVideoSizeBytes;
            case AUDIO -> maxAudioSizeBytes;
        };
        if (content.length > maxSize) {
            String label = switch (detected.type()) {
                case IMAGE -> "Image";
                case VIDEO -> "Video";
                case AUDIO -> "Audio message";
            };
            throw new FileTooLargeException(
                    label + " exceeds the maximum size of " + (maxSize / (1024 * 1024)) + "MB");
        }

        String storageKey = fileStorageService.store(CATEGORY, content, detected.extension());
        MessageAttachment attachment = new MessageAttachment(
                conversationId, uploaderId, detected.type(), storageKey, detected.mimeType(), content.length);

        if (detected.type() == AttachmentType.IMAGE) {
            int[] dimensions = AttachmentValidator.readImageDimensions(content);
            if (dimensions != null) {
                attachment.setDimensions(dimensions[0], dimensions[1]);
            }
            byte[] thumbnail = AttachmentValidator.generateThumbnail(content);
            if (thumbnail != null) {
                attachment.setThumbnailStorageKey(fileStorageService.store(THUMBNAIL_CATEGORY, thumbnail, "jpg"));
            }
        } else if (detected.type() == AttachmentType.AUDIO
                && durationSeconds != null
                && durationSeconds > 0
                && durationSeconds <= MAX_AUDIO_DURATION_SECONDS) {
            attachment.setDurationSeconds(durationSeconds);
        }

        String originalFilename = file.getOriginalFilename();
        if (originalFilename != null && originalFilename.length() <= 255) {
            attachment.setOriginalFilename(originalFilename);
        }

        return AttachmentResponse.from(attachmentRepository.save(attachment));
    }

    /**
     * Validates and consumes a set of the sender's own pending uploads into
     * the message being sent - all-or-nothing: any id that doesn't exist,
     * isn't pending, isn't in this conversation, or wasn't uploaded by this
     * sender fails the whole call, so a message is never left partially
     * attached.
     */
    @Transactional
    public List<MessageAttachment> attachPendingToMessage(
            List<UUID> attachmentIds, UUID conversationId, UUID senderId, UUID messageId) {
        if (attachmentIds == null || attachmentIds.isEmpty()) {
            return List.of();
        }

        List<MessageAttachment> attachments = attachmentRepository.findAllById(attachmentIds);
        if (attachments.size() != attachmentIds.size()) {
            throw new InvalidAttachmentException("One or more attachments could not be found");
        }
        for (MessageAttachment attachment : attachments) {
            if (!attachment.isPending()
                    || !attachment.getConversationId().equals(conversationId)
                    || !attachment.getUploaderId().equals(senderId)) {
                throw new InvalidAttachmentException("One or more attachments are not available to attach");
            }
        }

        attachments.forEach(attachment -> attachment.attachTo(messageId));
        return attachmentRepository.saveAll(attachments);
    }

    public List<MessageAttachment> findByMessageId(UUID messageId) {
        return attachmentRepository.findByMessageId(messageId);
    }

    /**
     * Loads the attachment and enforces access: while still pending, only
     * its uploader may reach it (e.g. a live preview before sending); once
     * attached to a message, any participant of that (non-deleted) message's
     * conversation may. Both "doesn't exist" and "not yours" resolve to the
     * same not-found error, so this never confirms or denies the existence
     * of a private attachment to someone outside it.
     */
    public MessageAttachment requireAccessible(UUID attachmentId, UUID userId) {
        MessageAttachment attachment = attachmentRepository
                .findById(attachmentId)
                .orElseThrow(() -> new NoSuchElementException("Attachment not found"));

        if (attachment.isPending()) {
            if (!attachment.getUploaderId().equals(userId)) {
                throw new NoSuchElementException("Attachment not found");
            }
            return attachment;
        }

        Message message = messageRepository
                .findById(attachment.getMessageId())
                .orElseThrow(() -> new NoSuchElementException("Attachment not found"));
        if (message.isDeleted()) {
            throw new NoSuchElementException("Attachment not found");
        }
        requireParticipant(attachment.getConversationId(), userId);
        return attachment;
    }

    /**
     * Decrypts and returns only {@code [startInclusive, endInclusive]} of
     * the attachment's plaintext bytes - see {@link
     * com.mobilemessenger.backend.storage.LocalFileStorageService#loadRange}.
     * Used for both a full download (range spanning the whole file) and an
     * HTTP range request (a seek within a video), so a large video is never
     * fully decrypted just to serve one small requested slice of it.
     */
    public byte[] loadRange(MessageAttachment attachment, long startInclusive, long endInclusive) {
        return fileStorageService.loadRange(CATEGORY, attachment.getStorageKey(), startInclusive, endInclusive);
    }

    public long sizeOf(MessageAttachment attachment) {
        return fileStorageService.size(CATEGORY, attachment.getStorageKey());
    }

    /** Thumbnails are small, so plain bytes (rather than a streamed {@link Resource}) are fine here. */
    public byte[] loadThumbnail(MessageAttachment attachment) {
        String thumbnailKey = attachment.getThumbnailStorageKey();
        if (thumbnailKey == null) {
            throw new NoSuchElementException("No thumbnail available");
        }
        return fileStorageService.load(THUMBNAIL_CATEGORY, thumbnailKey);
    }

    private void requireParticipant(UUID conversationId, UUID userId) {
        participantRepository
                .findByConversationIdAndUserId(conversationId, userId)
                .orElseThrow(() -> new NoSuchElementException("Chat not found"));
    }
}
