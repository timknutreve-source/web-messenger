package com.mobilemessenger.backend.chat.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record SendMessageRequest(
        @NotBlank(message = "Message content is required") @Size(max = 4000, message = "Message is too long")
                String content) {}
