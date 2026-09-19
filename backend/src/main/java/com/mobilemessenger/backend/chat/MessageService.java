package com.mobilemessenger.backend.chat;

import com.mobilemessenger.backend.chat.dto.MessagePageResponse;
import com.mobilemessenger.backend.chat.dto.MessageSearchResponse;
import com.mobilemessenger.backend.chat.dto.MessageResponse;
import com.mobilemessenger.backend.chat.exception.CannotActOnOwnMessageException;
import com.mobilemessenger.backend.chat.exception.InvalidMessageContentException;
import com.mobilemessenger.backend.chat.exception.InvalidSearchQueryException;
import com.mobilemessenger.backend.chat.exception.MessageAlreadyDeletedException;
import com.mobilemessenger.backend.chat.exception.NotMessageSenderException;
import com.mobilemessenger.backend.chat.poll.InvalidPollException;
import com.mobilemessenger.backend.chat.poll.PollService;
import com.mobilemessenger.backend.chat.poll.dto.PollResponse;
import com.mobilemessenger.backend.chat.websocket.ChatEvent;
import com.mobilemessenger.backend.chat.websocket.MessageDeletedPayload;
import com.mobilemessenger.backend.chat.websocket.MessagesReadPayload;
import com.mobilemessenger.backend.user.User;
import com.mobilemessenger.backend.user.UserRepository;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Locale;
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

    /** Search returns at most this many (most recent) matches, and scans the history in batches of this size. */
    static final int MAX_SEARCH_RESULTS = 200;
    private static final int SEARCH_BATCH_SIZE = 500;
    private static final int MAX_QUERY_LENGTH = 100;
    private static final int DEFAULT_PAGE_SIZE = 50;

    private final MessageRepository messageRepository;
    private final MessageAttachmentRepository attachmentRepository;
    private final ConversationRepository conversationRepository;
    private final ConversationParticipantRepository participantRepository;
    private final UserRepository userRepository;
    private final AttachmentService attachmentService;
    private final SimpMessagingTemplate messagingTemplate;
    private final GroupReceiptService groupReceiptService;
    private final PollService pollService;

    public MessageService(
            MessageRepository messageRepository,
            MessageAttachmentRepository attachmentRepository,
            ConversationRepository conversationRepository,
            ConversationParticipantRepository participantRepository,
            UserRepository userRepository,
            AttachmentService attachmentService,
            SimpMessagingTemplate messagingTemplate,
            GroupReceiptService groupReceiptService,
            PollService pollService) {
        this.groupReceiptService = groupReceiptService;
        this.pollService = pollService;
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

        // The page was fetched newest-first; clients render oldest-first.
        List<Message> chronological = new ArrayList<>(pageContent);
        Collections.reverse(chronological);
        return new MessagePageResponse(toResponses(chronological, userId), hasMore);
    }

    /**
     * Finds messages of this chat whose text contains {@code rawQuery}
     * (case-insensitive), oldest first, most recent {@link #MAX_SEARCH_RESULTS} at most.
     *
     * <p>Message text is encrypted at rest with a random nonce per value, so
     * the database cannot match it - no SQL {@code LIKE} could ever work.
     * Instead the history is read (and thereby decrypted) in batches and
     * matched here, in memory, one batch at a time. That is linear in the
     * chat's length; fine at this scale, and the only option without weakening
     * the encryption (a searchable index over plaintext would defeat it).
     */
    public MessageSearchResponse searchMessages(UUID conversationId, UUID userId, String rawQuery) {
        requireParticipant(conversationId, userId);

        String query = rawQuery == null ? "" : rawQuery.trim();
        if (query.isEmpty()) {
            throw new InvalidSearchQueryException("Enter some text to search for");
        }
        if (query.length() > MAX_QUERY_LENGTH) {
            throw new InvalidSearchQueryException("Search text must be at most " + MAX_QUERY_LENGTH + " characters");
        }
        String needle = query.toLowerCase(Locale.ROOT);

        List<Message> matches = new ArrayList<>();
        boolean truncated = false;
        int page = 0;
        scan:
        while (true) {
            List<Message> batch = messageRepository.findByConversationIdOrderByCreatedAtDescIdDesc(
                    conversationId, PageRequest.of(page, SEARCH_BATCH_SIZE));
            for (Message message : batch) {
                if (message.isDeleted() || message.getContent() == null) {
                    continue;
                }
                if (message.getContent().toLowerCase(Locale.ROOT).contains(needle)) {
                    if (matches.size() == MAX_SEARCH_RESULTS) {
                        truncated = true;
                        break scan;
                    }
                    matches.add(message);
                }
            }
            if (batch.size() < SEARCH_BATCH_SIZE) {
                break;
            }
            page++;
        }

        Collections.reverse(matches); // found newest-first, returned oldest-first
        return new MessageSearchResponse(toResponses(matches, userId), truncated);
    }

    /**
     * Turns messages (already in the order to return them) into responses,
     * batch-fetching attachments, senders and polls for the whole list rather
     * than per message, to avoid N+1 queries.
     */
    private List<MessageResponse> toResponses(List<Message> messages, UUID viewerId) {
        List<UUID> messageIds = messages.stream().map(Message::getId).toList();
        Map<UUID, List<MessageAttachment>> attachmentsByMessageId = attachmentRepository
                .findByMessageIdIn(messageIds)
                .stream()
                .collect(Collectors.groupingBy(MessageAttachment::getMessageId));
        Map<UUID, User> usersById = userRepository
                .findAllById(messages.stream().map(Message::getSenderId).distinct().toList())
                .stream()
                .collect(Collectors.toMap(User::getId, user -> user));
        Map<UUID, PollResponse> pollsByMessageId = pollService.toResponses(messages, viewerId);

        List<MessageResponse> responses = new ArrayList<>(messages.size());
        for (Message message : messages) {
            responses.add(MessageResponse.from(
                    message,
                    usersById.get(message.getSenderId()),
                    attachmentsByMessageId.getOrDefault(message.getId(), List.of()),
                    pollsByMessageId.get(message.getId())));
        }
        return responses;
    }

    @Transactional
    public MessageResponse editMessage(UUID conversationId, UUID messageId, UUID userId, String content) {
        Message message = requireOwnedMessage(conversationId, messageId, userId);
        if (message.isDeleted()) {
            throw new MessageAlreadyDeletedException();
        }
        if (pollService.isPollMessage(messageId)) {
            throw new InvalidPollException("A poll's question can't be edited");
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

        if (isGroup(conversationId)) {
            markGroupRead(conversationId, userId);
            return;
        }

        List<Message> unread =
                messageRepository.findByConversationIdAndSenderIdNotAndStatusNot(conversationId, userId, MessageStatus.READ);
        if (unread.isEmpty()) {
            return;
        }

        List<UUID> ids = unread.stream().map(Message::getId).toList();
        messageRepository.markReadIfNotRead(ids);
        broadcast(conversationId, "MESSAGES_READ", new MessagesReadPayload(ids));
    }

    /**
     * A group message only reaches READ once every recipient has read it, so
     * one member reading the chat records their own receipts and broadcasts
     * only the messages whose overall status actually advanced.
     */
    private void markGroupRead(UUID conversationId, UUID userId) {
        List<Message> unread = messageRepository.findUnreadInGroup(conversationId, userId);
        List<Message> advanced = groupReceiptService.recordRead(unread, userId);
        if (advanced.isEmpty()) {
            return;
        }
        messageRepository.saveAll(advanced);

        List<UUID> nowRead = advanced.stream()
                .filter(m -> m.getStatus() == MessageStatus.READ)
                .map(Message::getId)
                .toList();
        if (!nowRead.isEmpty()) {
            broadcast(conversationId, "MESSAGES_READ", new MessagesReadPayload(nowRead));
        }
        for (Message message : advanced) {
            if (message.getStatus() == MessageStatus.DELIVERED) {
                broadcast(conversationId, "MESSAGE_STATUS_UPDATED", toStatusResponse(message));
            }
        }
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

        if (isGroup(conversationId)) {
            // Delivered to this member only; the message's own status advances
            // once every recipient has it, and only then is it broadcast.
            if (groupReceiptService.recordDelivered(message, userId)) {
                messageRepository.save(message);
                broadcast(conversationId, "MESSAGE_STATUS_UPDATED", toStatusResponse(message));
            }
            return toStatusResponse(message);
        }

        boolean changed = messageRepository.markDeliveredIfSent(message.getId()) > 0;
        Message current = messageRepository.findById(message.getId()).orElse(message);

        MessageResponse response = toStatusResponse(current);
        if (changed) {
            broadcast(conversationId, "MESSAGE_STATUS_UPDATED", response);
        }
        return response;
    }

    private MessageResponse toStatusResponse(Message message) {
        return MessageResponse.from(
                message, findUser(message.getSenderId()), attachmentService.findByMessageId(message.getId()));
    }

    private boolean isGroup(UUID conversationId) {
        return conversationRepository.findById(conversationId).map(Conversation::isGroup).orElse(false);
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
