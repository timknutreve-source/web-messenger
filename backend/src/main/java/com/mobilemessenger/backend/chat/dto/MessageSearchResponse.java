package com.mobilemessenger.backend.chat.dto;

import java.util.List;

/**
 * Messages of one chat whose text contains the search query, oldest first.
 * {@code truncated} is true when there were more matches than are returned
 * (only the most recent ones are), so the client can say so.
 */
public record MessageSearchResponse(List<MessageResponse> results, boolean truncated) {}
