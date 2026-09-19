package com.mobilemessenger.backend.chat.poll;

import com.mobilemessenger.backend.chat.dto.MessageResponse;
import com.mobilemessenger.backend.chat.poll.dto.CreatePollRequest;
import com.mobilemessenger.backend.chat.poll.dto.PollResponse;
import com.mobilemessenger.backend.chat.poll.dto.VoteRequest;
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
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/chats/{chatId}/polls")
public class PollController {

    private final PollService pollService;

    public PollController(PollService pollService) {
        this.pollService = pollService;
    }

    @PostMapping
    public ResponseEntity<MessageResponse> create(
            Authentication authentication, @PathVariable UUID chatId, @Valid @RequestBody CreatePollRequest request) {
        MessageResponse response = pollService.createPoll(
                chatId, currentUserId(authentication), request.question(), request.options(), request.anonymous());
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @GetMapping("/{pollId}")
    public PollResponse get(Authentication authentication, @PathVariable UUID chatId, @PathVariable UUID pollId) {
        return pollService.getPoll(chatId, pollId, currentUserId(authentication));
    }

    /** Votes, or changes an existing vote to a different option. */
    @PutMapping("/{pollId}/vote")
    public PollResponse vote(
            Authentication authentication,
            @PathVariable UUID chatId,
            @PathVariable UUID pollId,
            @Valid @RequestBody VoteRequest request) {
        return pollService.vote(chatId, pollId, currentUserId(authentication), request.optionId());
    }

    @DeleteMapping("/{pollId}/vote")
    public PollResponse retract(Authentication authentication, @PathVariable UUID chatId, @PathVariable UUID pollId) {
        return pollService.retractVote(chatId, pollId, currentUserId(authentication));
    }

    private UUID currentUserId(Authentication authentication) {
        return (UUID) authentication.getPrincipal();
    }
}
