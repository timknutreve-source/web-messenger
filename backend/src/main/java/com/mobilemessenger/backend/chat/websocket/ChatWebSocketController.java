package com.mobilemessenger.backend.chat.websocket;

import com.mobilemessenger.backend.chat.ConversationParticipantRepository;
import com.mobilemessenger.backend.user.User;
import com.mobilemessenger.backend.user.UserRepository;
import java.security.Principal;
import java.util.NoSuchElementException;
import java.util.UUID;
import org.springframework.messaging.handler.annotation.DestinationVariable;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Controller;

/**
 * Typing indicators only. These are ephemeral and are never persisted as
 * messages - see {@code MessageService}, which owns every persisted
 * message event instead.
 */
@Controller
public class ChatWebSocketController {

    private final ConversationParticipantRepository participantRepository;
    private final UserRepository userRepository;
    private final SimpMessagingTemplate messagingTemplate;

    public ChatWebSocketController(
            ConversationParticipantRepository participantRepository,
            UserRepository userRepository,
            SimpMessagingTemplate messagingTemplate) {
        this.participantRepository = participantRepository;
        this.userRepository = userRepository;
        this.messagingTemplate = messagingTemplate;
    }

    /**
     * The sender's identity always comes from the authenticated STOMP
     * session ({@code principal}), never from the payload - a client can
     * only ever announce itself as typing, never spoof another user.
     */
    @MessageMapping("/chats/{chatId}/typing")
    public void typing(@DestinationVariable UUID chatId, @Payload TypingRequest request, Principal principal) {
        UUID userId = UUID.fromString(principal.getName());
        if (participantRepository.findByConversationIdAndUserId(chatId, userId).isEmpty()) {
            return;
        }

        User user = userRepository.findById(userId).orElseThrow(() -> new NoSuchElementException("User not found"));
        ChatEvent event = ChatEvent.of(
                request.started() ? "TYPING_STARTED" : "TYPING_STOPPED",
                new TypingEventPayload(userId, user.getUsername()));
        messagingTemplate.convertAndSend("/topic/chats/" + chatId, event);
    }
}
