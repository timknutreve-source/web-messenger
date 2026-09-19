package com.mobilemessenger.backend.chat.poll;

import com.mobilemessenger.backend.chat.Conversation;
import com.mobilemessenger.backend.chat.ConversationParticipantRepository;
import com.mobilemessenger.backend.chat.ConversationRepository;
import com.mobilemessenger.backend.chat.Message;
import com.mobilemessenger.backend.chat.MessageRepository;
import com.mobilemessenger.backend.chat.dto.MessageResponse;
import com.mobilemessenger.backend.chat.poll.dto.PollOptionResponse;
import com.mobilemessenger.backend.chat.poll.dto.PollResponse;
import com.mobilemessenger.backend.chat.poll.dto.PollUpdatedPayload;
import com.mobilemessenger.backend.chat.websocket.AfterCommit;
import com.mobilemessenger.backend.chat.websocket.ChatEvent;
import com.mobilemessenger.backend.contact.dto.ContactUserSummary;
import com.mobilemessenger.backend.user.User;
import com.mobilemessenger.backend.user.UserRepository;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.NoSuchElementException;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Polls in group chats: creating one, voting, changing or retracting a vote.
 *
 * <p>One vote per user per poll (changing it moves the vote, retracting
 * removes it). A public poll shows who voted for what; an anonymous poll only
 * ever exposes totals - the voter list is never sent for it, though the
 * server still remembers votes so they can be changed or retracted.
 */
@Service
public class PollService {

    static final int MAX_OPTION_LENGTH = 200;

    private final PollRepository pollRepository;
    private final PollOptionRepository optionRepository;
    private final PollVoteRepository voteRepository;
    private final MessageRepository messageRepository;
    private final ConversationRepository conversationRepository;
    private final ConversationParticipantRepository participantRepository;
    private final UserRepository userRepository;
    private final SimpMessagingTemplate messagingTemplate;

    public PollService(
            PollRepository pollRepository,
            PollOptionRepository optionRepository,
            PollVoteRepository voteRepository,
            MessageRepository messageRepository,
            ConversationRepository conversationRepository,
            ConversationParticipantRepository participantRepository,
            UserRepository userRepository,
            SimpMessagingTemplate messagingTemplate) {
        this.pollRepository = pollRepository;
        this.optionRepository = optionRepository;
        this.voteRepository = voteRepository;
        this.messageRepository = messageRepository;
        this.conversationRepository = conversationRepository;
        this.participantRepository = participantRepository;
        this.userRepository = userRepository;
        this.messagingTemplate = messagingTemplate;
    }

    /** Posts a poll to a group as a new message (its content is the question) and broadcasts it. */
    @Transactional
    public MessageResponse createPoll(
            UUID conversationId, UUID userId, String rawQuestion, List<String> rawOptions, boolean anonymous) {
        requireParticipant(conversationId, userId);
        Conversation conversation = conversationRepository.findById(conversationId).orElseThrow();
        if (!conversation.isGroup()) {
            throw new InvalidPollException("Polls can only be created in group chats");
        }

        String question = rawQuestion == null ? "" : rawQuestion.trim();
        if (question.isEmpty()) {
            throw new InvalidPollException("A poll needs a question");
        }
        List<String> options = cleanOptions(rawOptions);

        Message message = messageRepository.saveAndFlush(new Message(conversationId, userId, question));
        Poll poll = pollRepository.saveAndFlush(new Poll(conversationId, message.getId(), userId, anonymous));
        for (int i = 0; i < options.size(); i++) {
            optionRepository.save(new PollOption(poll.getId(), i, options.get(i)));
        }
        optionRepository.flush();

        conversation.touchActivity(message.getCreatedAt());
        conversationRepository.save(conversation);

        // Broadcast to the whole chat, so it carries no viewer-specific vote.
        MessageResponse response = MessageResponse.from(
                message, findUser(userId), List.of(), toResponses(List.of(message), null).get(message.getId()));
        messagingTemplate.convertAndSend("/topic/chats/" + conversationId, ChatEvent.of("NEW_MESSAGE", response));
        return response;
    }

    @Transactional
    public PollResponse vote(UUID conversationId, UUID pollId, UUID userId, UUID optionId) {
        Poll poll = requireVotablePoll(conversationId, pollId, userId);
        PollOption option = optionRepository.findByPollIdInOrderByPositionAsc(List.of(pollId)).stream()
                .filter(o -> o.getId().equals(optionId))
                .findFirst()
                .orElseThrow(() -> new InvalidPollException("That option doesn't belong to this poll"));

        PollVote existing = voteRepository.findByPollIdAndUserId(pollId, userId).orElse(null);
        if (existing == null) {
            voteRepository.saveAndFlush(new PollVote(pollId, option.getId(), userId));
        } else {
            existing.changeTo(option.getId());
            voteRepository.saveAndFlush(existing);
        }
        return afterChange(poll, userId);
    }

    @Transactional
    public PollResponse retractVote(UUID conversationId, UUID pollId, UUID userId) {
        Poll poll = requireVotablePoll(conversationId, pollId, userId);
        voteRepository.findByPollIdAndUserId(pollId, userId).ifPresent(voteRepository::delete);
        voteRepository.flush();
        return afterChange(poll, userId);
    }

    public boolean isPollMessage(UUID messageId) {
        return !pollRepository.findByMessageIdIn(List.of(messageId)).isEmpty();
    }

    public PollResponse getPoll(UUID conversationId, UUID pollId, UUID userId) {
        requireParticipant(conversationId, userId);
        Poll poll = pollRepository
                .findByIdAndConversationId(pollId, conversationId)
                .orElseThrow(() -> new NoSuchElementException("Poll not found"));
        Message message = messageRepository.findById(poll.getMessageId()).orElseThrow();
        PollResponse response = toResponses(List.of(message), userId).get(message.getId());
        if (response == null) {
            throw new NoSuchElementException("Poll not found");
        }
        return response;
    }

    /**
     * Builds each given message's poll (if it has one) as seen by
     * {@code viewerId} (null = a viewer-neutral broadcast copy). Batched so
     * loading a page of messages never costs a query per message. A deleted
     * message's poll is never returned.
     */
    public Map<UUID, PollResponse> toResponses(Collection<Message> messages, UUID viewerId) {
        Map<UUID, Message> liveMessages = messages.stream()
                .filter(m -> !m.isDeleted())
                .collect(Collectors.toMap(Message::getId, m -> m, (a, b) -> a));
        if (liveMessages.isEmpty()) {
            return Map.of();
        }
        List<Poll> polls = pollRepository.findByMessageIdIn(liveMessages.keySet());
        if (polls.isEmpty()) {
            return Map.of();
        }
        List<UUID> pollIds = polls.stream().map(Poll::getId).toList();
        Map<UUID, List<PollOption>> optionsByPoll = optionRepository.findByPollIdInOrderByPositionAsc(pollIds).stream()
                .collect(Collectors.groupingBy(PollOption::getPollId));
        Map<UUID, List<PollVote>> votesByPoll = voteRepository.findByPollIdInOrderByVotedAtAsc(pollIds).stream()
                .collect(Collectors.groupingBy(PollVote::getPollId));

        Set<UUID> voterIds = new HashSet<>();
        for (Poll poll : polls) {
            if (!poll.isAnonymous()) {
                votesByPoll.getOrDefault(poll.getId(), List.of()).forEach(v -> voterIds.add(v.getUserId()));
            }
        }
        Map<UUID, User> voters = userRepository.findAllById(voterIds).stream()
                .collect(Collectors.toMap(User::getId, u -> u));

        Map<UUID, PollResponse> result = new HashMap<>();
        for (Poll poll : polls) {
            List<PollVote> votes = votesByPoll.getOrDefault(poll.getId(), List.of());
            List<PollOptionResponse> options = new ArrayList<>();
            for (PollOption option : optionsByPoll.getOrDefault(poll.getId(), List.of())) {
                List<PollVote> forOption =
                        votes.stream().filter(v -> v.getOptionId().equals(option.getId())).toList();
                List<ContactUserSummary> optionVoters = poll.isAnonymous()
                        ? null
                        : forOption.stream().map(v -> ContactUserSummary.from(voters.get(v.getUserId()))).toList();
                options.add(new PollOptionResponse(option.getId(), option.getText(), forOption.size(), optionVoters));
            }
            UUID myOption = viewerId == null
                    ? null
                    : votes.stream().filter(v -> v.getUserId().equals(viewerId)).map(PollVote::getOptionId)
                            .findFirst().orElse(null);
            result.put(
                    poll.getMessageId(),
                    new PollResponse(
                            poll.getId(),
                            poll.getMessageId(),
                            liveMessages.get(poll.getMessageId()).getContent(),
                            poll.isAnonymous(),
                            options,
                            votes.size(),
                            myOption));
        }
        return result;
    }

    // ---- helpers ----

    private PollResponse afterChange(Poll poll, UUID userId) {
        ChatEvent event = ChatEvent.of("POLL_UPDATED", new PollUpdatedPayload(poll.getId(), poll.getMessageId()));
        AfterCommit.run(() -> messagingTemplate.convertAndSend("/topic/chats/" + poll.getConversationId(), event));
        Message message = messageRepository.findById(poll.getMessageId()).orElseThrow();
        return toResponses(List.of(message), userId).get(message.getId());
    }

    private Poll requireVotablePoll(UUID conversationId, UUID pollId, UUID userId) {
        requireParticipant(conversationId, userId);
        Poll poll = pollRepository
                .findByIdAndConversationId(pollId, conversationId)
                .orElseThrow(() -> new NoSuchElementException("Poll not found"));
        Message message = messageRepository.findById(poll.getMessageId()).orElseThrow();
        if (message.isDeleted()) {
            throw new InvalidPollException("This poll was deleted");
        }
        return poll;
    }

    private List<String> cleanOptions(List<String> raw) {
        List<String> cleaned = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        for (String option : raw == null ? List.<String>of() : raw) {
            String text = option == null ? "" : option.trim();
            if (text.isEmpty()) {
                throw new InvalidPollException("Poll options can't be empty");
            }
            if (text.length() > MAX_OPTION_LENGTH) {
                throw new InvalidPollException("Poll options must be at most " + MAX_OPTION_LENGTH + " characters");
            }
            if (!seen.add(text.toLowerCase(Locale.ROOT))) {
                throw new InvalidPollException("Poll options must all be different");
            }
            cleaned.add(text);
        }
        if (cleaned.size() < 2 || cleaned.size() > 10) {
            throw new InvalidPollException("A poll needs between 2 and 10 options");
        }
        return cleaned;
    }

    private void requireParticipant(UUID conversationId, UUID userId) {
        participantRepository
                .findByConversationIdAndUserId(conversationId, userId)
                .orElseThrow(() -> new NoSuchElementException("Chat not found"));
    }

    private User findUser(UUID userId) {
        return userRepository.findById(userId).orElseThrow(() -> new NoSuchElementException("User not found"));
    }
}
