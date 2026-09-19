package com.mobilemessenger.backend.chat.poll.dto;

import java.util.UUID;

/**
 * Payload of the {@code POLL_UPDATED} chat event. It deliberately carries no
 * results: a poll is personal to each viewer (their own vote, and in an
 * anonymous poll what may be shown), so each client refetches it.
 */
public record PollUpdatedPayload(UUID pollId, UUID messageId) {}
