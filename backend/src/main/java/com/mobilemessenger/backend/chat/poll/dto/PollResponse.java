package com.mobilemessenger.backend.chat.poll.dto;

import java.util.List;
import java.util.UUID;

/**
 * A poll as one particular viewer sees it. {@code myOptionId} is the
 * viewer's own vote (or null); it is what makes the same poll personal to
 * each member, so a poll broadcast to a whole chat carries {@code null}
 * here and each client keeps/refetches its own.
 */
public record PollResponse(
        UUID id,
        UUID messageId,
        String question,
        boolean anonymous,
        List<PollOptionResponse> options,
        int totalVotes,
        UUID myOptionId) {}
