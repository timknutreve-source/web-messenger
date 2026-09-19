package com.mobilemessenger.backend.chat;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;
import org.springframework.stereotype.Service;

/**
 * Delivery/read state for messages in a <em>group</em>, where one message has
 * many recipients. The message's own status is kept as an aggregate, the way
 * messaging apps show a single tick state for a group message:
 * <ul>
 *   <li>{@code DELIVERED} once every recipient has received it;
 *   <li>{@code READ} once every recipient has read it.
 * </ul>
 * A recipient is every member other than the sender who had already joined
 * when the message was sent - someone who joins later never received it, so
 * they must not hold it back from ever counting as read.
 */
@Service
public class GroupReceiptService {

    private final MessageReceiptRepository receiptRepository;
    private final ConversationParticipantRepository participantRepository;

    public GroupReceiptService(
            MessageReceiptRepository receiptRepository, ConversationParticipantRepository participantRepository) {
        this.receiptRepository = receiptRepository;
        this.participantRepository = participantRepository;
    }

    /** Records that {@code userId} received {@code message}; returns whether its aggregate status advanced. */
    public boolean recordDelivered(Message message, UUID userId) {
        MessageReceipt receipt = receiptRepository
                .findByMessageIdAndUserId(message.getId(), userId)
                .orElseGet(() -> new MessageReceipt(message.getId(), userId));
        receipt.markDelivered(Instant.now());
        receiptRepository.save(receipt);
        return recompute(List.of(message)).contains(message);
    }

    /** Records that {@code userId} read every message in {@code messages}; returns those whose aggregate status advanced. */
    public List<Message> recordRead(List<Message> messages, UUID userId) {
        if (messages.isEmpty()) {
            return List.of();
        }
        Map<UUID, MessageReceipt> existing = receiptRepository
                .findByMessageIdIn(messages.stream().map(Message::getId).toList())
                .stream()
                .filter(r -> r.getUserId().equals(userId))
                .collect(Collectors.toMap(MessageReceipt::getMessageId, Function.identity()));
        Instant now = Instant.now();
        for (Message message : messages) {
            MessageReceipt receipt = existing.getOrDefault(message.getId(), new MessageReceipt(message.getId(), userId));
            receipt.markRead(now);
            receiptRepository.save(receipt);
        }
        return recompute(messages);
    }

    /** Recomputes each message's aggregate status from its receipts; returns the ones that changed. */
    private List<Message> recompute(List<Message> messages) {
        UUID conversationId = messages.get(0).getConversationId();
        List<ConversationParticipant> members = participantRepository.findByConversationId(conversationId);
        Map<UUID, List<MessageReceipt>> receiptsByMessage = receiptRepository
                .findByMessageIdIn(messages.stream().map(Message::getId).toList())
                .stream()
                .collect(Collectors.groupingBy(MessageReceipt::getMessageId));

        List<Message> changed = new ArrayList<>();
        for (Message message : messages) {
            Map<UUID, MessageReceipt> byUser = receiptsByMessage.getOrDefault(message.getId(), List.of()).stream()
                    .collect(Collectors.toMap(MessageReceipt::getUserId, Function.identity()));
            List<UUID> recipients = members.stream()
                    .filter(m -> !m.getUserId().equals(message.getSenderId()))
                    .filter(m -> !m.getJoinedAt().isAfter(message.getCreatedAt()))
                    .map(ConversationParticipant::getUserId)
                    .toList();
            if (recipients.isEmpty()) {
                continue;
            }
            boolean allRead = recipients.stream().allMatch(id -> byUser.containsKey(id) && byUser.get(id).isRead());
            boolean allDelivered =
                    recipients.stream().allMatch(id -> byUser.containsKey(id) && byUser.get(id).isDelivered());

            MessageStatus before = message.getStatus();
            if (allRead) {
                message.markRead();
            } else if (allDelivered) {
                message.markDelivered();
            }
            if (message.getStatus() != before) {
                changed.add(message);
            }
        }
        return changed;
    }
}
