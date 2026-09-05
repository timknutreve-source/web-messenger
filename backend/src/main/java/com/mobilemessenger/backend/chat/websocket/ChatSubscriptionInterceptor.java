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
 * Rejects a SUBSCRIBE to {@code /topic/chats/{chatId}} unless the
 * authenticated STOMP session's user is actually a participant of that
 * conversation - Spring's simple broker has no idea a destination like this
 * is private, so this is the only thing standing between "any authenticated
 * user" and "someone else's conversation".
 */
@Component
public class ChatSubscriptionInterceptor implements ChannelInterceptor {

    private static final Pattern CHAT_TOPIC_PATTERN = Pattern.compile("^/topic/chats/([0-9a-fA-F-]{36})$");

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
        Matcher matcher = destination == null ? null : CHAT_TOPIC_PATTERN.matcher(destination);
        if (matcher == null || !matcher.matches()) {
            return message;
        }

        Principal user = accessor.getUser();
        if (user == null) {
            throw new MessagingException("Authentication required");
        }

        UUID chatId = UUID.fromString(matcher.group(1));
        UUID userId = UUID.fromString(user.getName());
        boolean isParticipant =
                participantRepository.findByConversationIdAndUserId(chatId, userId).isPresent();
        if (!isParticipant) {
            throw new MessagingException("Not authorized to subscribe to this conversation");
        }

        return message;
    }
}
