package com.mobilemessenger.backend.chat;

import com.mobilemessenger.backend.chat.dto.MessagePageResponse;
import com.mobilemessenger.backend.chat.dto.MessageResponse;
import com.mobilemessenger.backend.chat.exception.CannotActOnOwnMessageException;
import com.mobilemessenger.backend.chat.exception.InvalidMessageContentException;
import com.mobilemessenger.backend.chat.exception.MessageAlreadyDeletedException;
import com.mobilemessenger.backend.chat.exception.NotMessageSenderException;
import com.mobilemessenger.backend.chat.websocket.ChatEvent;
import com.mobilemessenger.backend.chat.websocket.MessageDeletedPayload;
import com.mobilemessenger.backend.chat.websocket.MessagesReadPayload;
import com.mobilemessenger.backend.user.User;
import com.mobilemessenger.backend.user.UserRepository;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;
import java.util.UUID;
import java.util.stream.Collectors;
import org.springframework.data.domain.PageRequest;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class MessageService {

    /** Capped so a single request can never pull in an unbounded conversation history. */
    static final int MAX_PAGE_SIZE = 100;
    private static final int DEFAULT_PAGE_SIZE = 50;

    private final MessageRepository messageRepository;
    private final MessageAttachmentRepository attachmentRepository;
    private final ConversationRepository conversationRepository;
    private final ConversationParticipantRepository participantRepository;
    private final UserRepository userRepository;
    private final AttachmentService attachmentService;
    private final SimpMessagingTemplate messagingTemplate;

    public MessageService(
            MessageRepository messageRepository,
            MessageAttachmentRepository attachmentRepository,
            ConversationRepository conversationRepository,
            ConversationParticipantRepository participantRepository,
            UserRepository userRepository,
            AttachmentService attachmentService,
            SimpMessagingTemplate messagingTemplate) {
        this.messageRepository = messageRepository;
        this.attachmentRepository = attachmentRepository;
        this.conversationRepository = conversationRepository;
        this.participantRepository = participantRepository;
        this.userRepository = userRepository;
        this.attachmentService = attachmentService;
        this.messagingTemplate = messagingTemplate;
    }

    @Transactional
    public MessageResponse sendMessage(UUID conversationId, UUID senderId, String content, List<UUID> attachmentIds) {
        requireParticipant(conversationId, senderId);

        String trimmedContent = content == null ? "" : content.trim();
        List<UUID> ids = attachmentIds == null ? List.of() : attachmentIds;
        if (trimmedContent.isEmpty() && ids.isEmpty()) {
            throw new InvalidMessageContentException();
        }

        Message message = messageRepository.saveAndFlush(new Message(conversationId, senderId, trimmedContent));
        List<MessageAttachment> attachments =
                attachmentService.attachPendingToMessage(ids, conversationId, senderId, message.getId());

        Conversation conversation = conversationRepository.findById(conversationId).orElseThrow();
        conversation.touchActivity(message.getCreatedAt());
        conversationRepository.save(conversation);

        MessageResponse response = MessageResponse.from(message, findUser(senderId), attachments);
        broadcast(conversationId, "NEW_MESSAGE", response);
        return response;
    }

    public MessagePageResponse loadMessages(UUID conversationId, UUID userId, UUID before, Integer limit) {
        requireParticipant(conversationId, userId);

        int pageSize = limit == null ? DEFAULT_PAGE_SIZE : Math.max(1, Math.min(limit, MAX_PAGE_SIZE));
        PageRequest pageRequest = PageRequest.of(0, pageSize + 1);

        List<Message> page;
        if (before == null) {
            page = messageRepository.findByConversationIdOrderByCreatedAtDescIdDesc(conversationId, pageRequest);
        } else {
            Message cursor = messageRepository
                    .findByIdAndConversationId(before, conversationId)
                    .orElseThrow(() -> new NoSuchElementException("Message not found"));
            page = messageRepository.findPageBefore(conversationId, cursor.getCreatedAt(), cursor.getId(), pageRequest);
        }

        boolean hasMore = page.size() > pageSize;
        List<Message> pageContent = hasMore ? page.subList(0, pageSize) : page;

        // Batch-fetch attachments and senders for the whole page rather than
        // per-message, to avoid N+1 queries.
        Map<UUID, List<MessageAttachment>> attachmentsByMessageId = attachmentRepository
                .findByMessageIdIn(pageContent.stream().map(Message::getId).toList())
                .stream()
                .collect(Collectors.groupingBy(MessageAttachment::getMessageId));
        Map<UUID, User> usersById = userRepository
                .findAllById(pageContent.stream().map(Message::getSenderId).distinct().toList())
                .stream()
                .collect(Collectors.toMap(User::getId, user -> user));

        List<MessageResponse> responses = new ArrayList<>(pageContent.size());
        for (int i = pageContent.size() - 1; i >= 0; i--) {
            Message message = pageContent.get(i);
            responses.add(MessageResponse.from(
                    message,
                    usersById.get(message.getSenderId()),
                    attachmentsByMessageId.getOrDefault(message.getId(), List.of())));
        }
        return new MessagePageResponse(responses, hasMore);
    }

    @Transactional
    public MessageResponse editMessage(UUID conversationId, UUID messageId, UUID userId, String content) {
        Message message = requireOwnedMessage(conversationId, messageId, userId);
        if (message.isDeleted()) {
            throw new MessageAlreadyDeletedException();
        }

        message.edit(content.trim());
        messageRepository.save(message);

        MessageResponse response =
                MessageResponse.from(message, findUser(userId), attachmentService.findByMessageId(messageId));
        broadcast(conversationId, "MESSAGE_UPDATED", response);
        return response;
    }

    @Transactional
    public void deleteMessage(UUID conversationId, UUID messageId, UUID userId) {
        Message message = requireOwnedMessage(conversationId, messageId, userId);
        if (message.isDeleted()) {
            return;
        }

        message.softDelete();
        messageRepository.save(message);
        broadcast(conversationId, "MESSAGE_DELETED", new MessageDeletedPayload(messageId));
    }

    @Transactional
    public void markRead(UUID conversationId, UUID userId) {
        requireParticipant(conversationId, userId);

        List<Message> unread =
                messageRepository.findByConversationIdAndSenderIdNotAndStatusNot(conversationId, userId, MessageStatus.READ);
        if (unread.isEmpty()) {
            return;
        }

        List<UUID> changedIds = new ArrayList<>(unread.size());
        for (Message message : unread) {
            message.markRead();
            changedIds.add(message.getId());
        }
        messageRepository.saveAll(unread);
        broadcast(conversationId, "MESSAGES_READ", new MessagesReadPayload(changedIds));
    }

    @Transactional
    public MessageResponse markDelivered(UUID conversationId, UUID messageId, UUID userId) {
        requireParticipant(conversationId, userId);
        Message message = messageRepository
                .findByIdAndConversationId(messageId, conversationId)
                .orElseThrow(() -> new NoSuchElementException("Message not found"));

        if (message.getSenderId().equals(userId)) {
            throw new CannotActOnOwnMessageException();
        }

        message.markDelivered();
        messageRepository.save(message);

        MessageResponse response = MessageResponse.from(
                message, findUser(message.getSenderId()), attachmentService.findByMessageId(messageId));
        broadcast(conversationId, "MESSAGE_STATUS_UPDATED", response);
        return response;
    }

    /**
     * Loads the message and enforces both that it belongs to the given
     * conversation and that {@code userId} is its sender - the caller must
     * already be confirmed as a participant of the conversation via {@link
     * #requireParticipant}, so this only ever distinguishes "not yours" from
     * "not found", never leaks whether an inaccessible conversation exists.
     */
    private Message requireOwnedMessage(UUID conversationId, UUID messageId, UUID userId) {
        requireParticipant(conversationId, userId);
        Message message = messageRepository
                .findByIdAndConversationId(messageId, conversationId)
                .orElseThrow(() -> new NoSuchElementException("Message not found"));
        if (!message.getSenderId().equals(userId)) {
            throw new NotMessageSenderException();
        }
        return message;
    }

    private void requireParticipant(UUID conversationId, UUID userId) {
        participantRepository
                .findByConversationIdAndUserId(conversationId, userId)
                .orElseThrow(() -> new NoSuchElementException("Chat not found"));
    }

    private User findUser(UUID userId) {
        return userRepository.findById(userId).orElseThrow(() -> new NoSuchElementException("User not found"));
    }

    private void broadcast(UUID conversationId, String type, Object payload) {
        messagingTemplate.convertAndSend("/topic/chats/" + conversationId, ChatEvent.of(type, payload));
    }
}
