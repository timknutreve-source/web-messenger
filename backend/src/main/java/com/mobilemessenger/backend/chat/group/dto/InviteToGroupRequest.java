package com.mobilemessenger.backend.chat.group.dto;

import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;

public record InviteToGroupRequest(
        @NotEmpty(message = "Choose at least one contact to invite")
        @Size(max = 50, message = "At most 50 people can be invited at once")
        List<UUID> userIds) {}
