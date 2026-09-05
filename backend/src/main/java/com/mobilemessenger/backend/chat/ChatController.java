package com.mobilemessenger.backend.chat;

import com.mobilemessenger.backend.chat.dto.ChatSummaryResponse;
import java.util.List;
import java.util.UUID;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/chats")
public class ChatController {

    private final ChatService chatService;

    public ChatController(ChatService chatService) {
        this.chatService = chatService;
    }

    @GetMapping
    public List<ChatSummaryResponse> activeChats(Authentication authentication) {
        return chatService.listActiveChats(currentUserId(authentication));
    }

    @GetMapping("/archived")
    public List<ChatSummaryResponse> archivedChats(Authentication authentication) {
        return chatService.listArchivedChats(currentUserId(authentication));
    }

    @PostMapping("/{chatId}/archive")
    public ChatSummaryResponse archive(Authentication authentication, @PathVariable UUID chatId) {
        return chatService.archiveChat(chatId, currentUserId(authentication));
    }

    @PostMapping("/{chatId}/unarchive")
    public ChatSummaryResponse unarchive(Authentication authentication, @PathVariable UUID chatId) {
        return chatService.unarchiveChat(chatId, currentUserId(authentication));
    }

    private UUID currentUserId(Authentication authentication) {
        return (UUID) authentication.getPrincipal();
    }
}
