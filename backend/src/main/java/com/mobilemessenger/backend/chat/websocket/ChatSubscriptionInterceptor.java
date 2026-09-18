package com.mobilemessenger.backend.chat.websocket;

import com.mobilemessenger.backend.chat.ConversationParticipantRepository;
import java.security.Principal;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.MessagingException;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.ChannelInterceptor;
import org.springframework.stereotype.Component;

/**
 * Rejects a SUBSCRIBE to a private per-user or per-conversation topic
 * unless the authenticated STOMP session's user is actually allowed to see
 * it - Spring's simple broker has no idea a destination like this is
 * private, so this is the only thing standing between "any authenticated
 * user" and someone else's conversation or personal event feed:
 * <ul>
 *   <li>{@code /topic/chats/{chatId}} - only a participant of that conversation.
 *   <li>{@code /topic/users/{userId}/invitations} - only that exact user
 *       (their own incoming-invitation feed, see {@code ContactInvitationService}).
 * </ul>
 */
@Component
public class ChatSubscriptionInterceptor implements ChannelInterceptor {

    private static final Pattern CHAT_TOPIC_PATTERN = Pattern.compile("^/topic/chats/([0-9a-fA-F-]{36})$");
    private static final Pattern USER_INVITATIONS_TOPIC_PATTERN =
            Pattern.compile("^/topic/users/([0-9a-fA-F-]{36})/invitations$");

    private final ConversationParticipantRepository participantRepository;

    public ChatSubscriptionInterceptor(ConversationParticipantRepository participantRepository) {
        this.participantRepository = participantRepository;
    }

    @Override
    public Message<?> preSend(Message<?> message, MessageChannel channel) {
        StompHeaderAccessor accessor = StompHeaderAccessor.wrap(message);
        if (!StompCommand.SUBSCRIBE.equals(accessor.getCommand())) {
            return message;
        }

        String destination = accessor.getDestination();
        if (destination == null) {
            return message;
        }

        Matcher chatMatcher = CHAT_TOPIC_PATTERN.matcher(destination);
        if (chatMatcher.matches()) {
            UUID chatId = UUID.fromString(chatMatcher.group(1));
            UUID userId = requireUserId(accessor);
            boolean isParticipant =
                    participantRepository.findByConversationIdAndUserId(chatId, userId).isPresent();
            if (!isParticipant) {
                throw new MessagingException("Not authorized to subscribe to this conversation");
            }
            return message;
        }

        Matcher invitationsMatcher = USER_INVITATIONS_TOPIC_PATTERN.matcher(destination);
        if (invitationsMatcher.matches()) {
            UUID topicUserId = UUID.fromString(invitationsMatcher.group(1));
            UUID userId = requireUserId(accessor);
            if (!topicUserId.equals(userId)) {
                throw new MessagingException("Not authorized to subscribe to another user's invitations");
            }
            return message;
        }

        return message;
    }

    private UUID requireUserId(StompHeaderAccessor accessor) {
        Principal user = accessor.getUser();
        if (user == null) {
            throw new MessagingException("Authentication required");
        }
        return UUID.fromString(user.getName());
    }
}
