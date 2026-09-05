package com.mobilemessenger.backend.chat;

import com.mobilemessenger.backend.chat.dto.EditMessageRequest;
import com.mobilemessenger.backend.chat.dto.MessagePageResponse;
import com.mobilemessenger.backend.chat.dto.MessageResponse;
import com.mobilemessenger.backend.chat.dto.SendMessageRequest;
import jakarta.validation.Valid;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/chats/{chatId}/messages")
public class MessageController {

    private final MessageService messageService;

    public MessageController(MessageService messageService) {
        this.messageService = messageService;
    }

    @GetMapping
    public MessagePageResponse loadMessages(
            Authentication authentication,
            @PathVariable UUID chatId,
            @RequestParam(required = false) UUID before,
            @RequestParam(required = false) Integer limit) {
        return messageService.loadMessages(chatId, currentUserId(authentication), before, limit);
    }

    @PostMapping
    public ResponseEntity<MessageResponse> send(
            Authentication authentication, @PathVariable UUID chatId, @Valid @RequestBody SendMessageRequest request) {
        MessageResponse response = messageService.sendMessage(
                chatId, currentUserId(authentication), request.content(), request.attachmentIds());
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @PutMapping("/{messageId}")
    public MessageResponse edit(
            Authentication authentication,
            @PathVariable UUID chatId,
            @PathVariable UUID messageId,
            @Valid @RequestBody EditMessageRequest request) {
        return messageService.editMessage(chatId, messageId, currentUserId(authentication), request.content());
    }

    @DeleteMapping("/{messageId}")
    public ResponseEntity<Void> delete(
            Authentication authentication, @PathVariable UUID chatId, @PathVariable UUID messageId) {
        messageService.deleteMessage(chatId, messageId, currentUserId(authentication));
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/read")
    public ResponseEntity<Void> markRead(Authentication authentication, @PathVariable UUID chatId) {
        messageService.markRead(chatId, currentUserId(authentication));
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/{messageId}/delivered")
    public MessageResponse markDelivered(
            Authentication authentication, @PathVariable UUID chatId, @PathVariable UUID messageId) {
        return messageService.markDelivered(chatId, messageId, currentUserId(authentication));
    }

    private UUID currentUserId(Authentication authentication) {
        return (UUID) authentication.getPrincipal();
    }
}
