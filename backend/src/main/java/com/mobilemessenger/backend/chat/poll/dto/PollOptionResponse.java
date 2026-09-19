package com.mobilemessenger.backend.chat.poll.dto;

import com.mobilemessenger.backend.contact.dto.ContactUserSummary;
import java.util.List;
import java.util.UUID;

/**
 * {@code voters} lists who voted for this option in a public poll, and is
 * {@code null} - never an empty list - in an anonymous one, so an anonymous
 * poll cannot even hint at who voted.
 */
public record PollOptionResponse(UUID id, String text, int voteCount, List<ContactUserSummary> voters) {}
