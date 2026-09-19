package com.mobilemessenger.backend.chat.poll.dto;

import jakarta.validation.constraints.NotNull;
import java.util.UUID;

public record VoteRequest(@NotNull(message = "Choose an option") UUID optionId) {}
