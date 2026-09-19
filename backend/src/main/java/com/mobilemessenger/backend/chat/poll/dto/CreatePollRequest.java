package com.mobilemessenger.backend.chat.poll.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.util.List;

public record CreatePollRequest(
        @NotBlank(message = "A poll needs a question")
        @Size(max = 500, message = "The question must be at most 500 characters")
        String question,

        @NotNull(message = "A poll needs options")
        @Size(min = 2, max = 10, message = "A poll needs between 2 and 10 options")
        List<String> options,

        boolean anonymous) {}
