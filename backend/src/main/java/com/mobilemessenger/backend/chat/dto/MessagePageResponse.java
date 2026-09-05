package com.mobilemessenger.backend.chat.dto;

import java.util.List;

/**
 * A page of messages in chronological (oldest-first) order, ready to render
 * directly. {@code hasMore} tells the client whether an older page exists to
 * fetch (pass the oldest message's {@code id} back as {@code before}).
 */
public record MessagePageResponse(List<MessageResponse> messages, boolean hasMore) {}
