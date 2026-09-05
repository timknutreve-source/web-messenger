package com.mobilemessenger.backend.chat;

import com.mobilemessenger.backend.chat.dto.ChatSummaryResponse;
import com.mobilemessenger.backend.chat.dto.MessagePreviewResponse;
import com.mobilemessenger.backend.contact.dto.ContactUserSummary;
import com.mobilemessenger.backend.user.User;
import com.mobilemessenger.backend.user.UserRepository;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;
import java.util.UUID;
import java.util.stream.Collectors;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ChatService {

    private final ConversationRepository conversationRepository;
    private final ConversationParticipantRepository participantRepository;
    private final UserRepository userRepository;
    private final MessageRepository messageRepository;

    public ChatService(
            ConversationRepository conversationRepository,
            ConversationParticipantRepository participantRepository,
            UserRepository userRepository,
            MessageRepository messageRepository) {
        this.conversationRepository = conversationRepository;
        this.participantRepository = participantRepository;
        this.userRepository = userRepository;
        this.messageRepository = messageRepository;
    }

    /**
     * Returns (or lazily creates) the single direct conversation between two
     * users. Idempotent: calling this repeatedly for the same pair, in
     * either order, never creates more than one conversation - the ordered
     * pair lookup plus the database's partial unique index (see
     * V5__add_conversations.sql) are the two layers guarding against
     * duplicates. Intended to be called from within the same transaction as
     * contact creation (see ContactInvitationService.acceptInvitation).
     */
    @Transactional
    public Conversation getOrCreateDirectConversation(UUID userIdA, UUID userIdB) {
        // UUID.compareTo() compares the two halves as signed longs, which
        // disagrees with PostgreSQL's byte-wise uuid comparison (used by the
        // conversations_direct_pair_ordered CHECK constraint) whenever the
        // sign bit of either half differs between the two UUIDs. Comparing
        // the canonical string form instead matches Postgres's ordering,
        // since hex-digit ASCII order matches unsigned big-endian byte order.
        boolean aIsLower = userIdA.toString().compareTo(userIdB.toString()) < 0;
        UUID low = aIsLower ? userIdA : userIdB;
        UUID high = aIsLower ? userIdB : userIdA;

        return conversationRepository.findByDirectUserAIdAndDirectUserBId(low, high).orElseGet(() -> {
            Conversation conversation = conversationRepository.saveAndFlush(new Conversation(low, high));
            participantRepository.saveAndFlush(new ConversationParticipant(conversation.getId(), low));
            participantRepository.saveAndFlush(new ConversationParticipant(conversation.getId(), high));
            return conversation;
        });
    }

    public List<ChatSummaryResponse> listActiveChats(UUID userId) {
        return listChats(userId, false);
    }

    public List<ChatSummaryResponse> listArchivedChats(UUID userId) {
        return listChats(userId, true);
    }

    @Transactional
    public ChatSummaryResponse archiveChat(UUID conversationId, UUID userId) {
        ConversationParticipant participant = requireParticipant(conversationId, userId);
        if (!participant.isArchived()) {
            participant.archive();
            participantRepository.save(participant);
        }
        return toResponse(participant);
    }

    @Transactional
    public ChatSummaryResponse unarchiveChat(UUID conversationId, UUID userId) {
        ConversationParticipant participant = requireParticipant(conversationId, userId);
        if (participant.isArchived()) {
            participant.unarchive();
            participantRepository.save(participant);
        }
        return toResponse(participant);
    }

    /**
     * Looks up the caller's own membership row for a conversation. Used for
     * both archive/unarchive and to enforce access control: a user who is
     * not a participant gets the same 404 as a conversation that doesn't
     * exist at all, so this never confirms or denies the existence of a
     * private chat to someone outside it.
     */
    private ConversationParticipant requireParticipant(UUID conversationId, UUID userId) {
        return participantRepository
                .findByConversationIdAndUserId(conversationId, userId)
                .orElseThrow(() -> new NoSuchElementException("Chat not found"));
    }

    private List<ChatSummaryResponse> listChats(UUID userId, boolean archived) {
        List<ConversationParticipant> memberships = participantRepository.findByUserIdAndArchived(userId, archived);
        if (memberships.isEmpty()) {
            return List.of();
        }

        Map<UUID, Conversation> conversationsById = conversationRepository
                .findAllById(memberships.stream().map(ConversationParticipant::getConversationId).toList())
                .stream()
                .collect(Collectors.toMap(Conversation::getId, conversation -> conversation));

        Map<UUID, User> otherUsersById = userRepository
                .findAllById(memberships.stream()
                        .map(membership -> conversationsById.get(membership.getConversationId()).otherUserId(userId))
                        .toList())
                .stream()
                .collect(Collectors.toMap(User::getId, user -> user));

        return memberships.stream()
                .map(membership -> {
                    Conversation conversation = conversationsById.get(membership.getConversationId());
                    User otherUser = otherUsersById.get(conversation.otherUserId(userId));
                    return new ChatSummaryResponse(
                            conversation.getId(),
                            ContactUserSummary.from(otherUser),
                            conversation.getLastActivityAt(),
                            membership.isArchived(),
                            lastMessagePreview(conversation.getId()));
                })
                .sorted(Comparator.comparing(ChatSummaryResponse::lastActivityAt).reversed())
                .toList();
    }

    private ChatSummaryResponse toResponse(ConversationParticipant participant) {
        Conversation conversation = conversationRepository
                .findById(participant.getConversationId())
                .orElseThrow(() -> new NoSuchElementException("Chat not found"));
        User otherUser = userRepository
                .findById(conversation.otherUserId(participant.getUserId()))
                .orElseThrow(() -> new NoSuchElementException("User not found"));
        return new ChatSummaryResponse(
                conversation.getId(),
                ContactUserSummary.from(otherUser),
                conversation.getLastActivityAt(),
                participant.isArchived(),
                lastMessagePreview(conversation.getId()));
    }

    /**
     * The chat list is written per-conversation (one lookup each) rather
     * than one batched query for all of a user's conversations - simpler,
     * and the chat-list size for a single user is small enough in practice
     * that this isn't a performance concern; worth revisiting with a
     * windowed query if that ever changes.
     */
    private MessagePreviewResponse lastMessagePreview(UUID conversationId) {
        return messageRepository
                .findFirstByConversationIdOrderByCreatedAtDescIdDesc(conversationId)
                .map(MessagePreviewResponse::from)
                .orElse(null);
    }
}
