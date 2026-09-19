package com.mobilemessenger.backend.chat.group.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;

public record CreateGroupRequest(
        @NotBlank(message = "Group name is required")
        @Size(max = 100, message = "Group name must be at most 100 characters")
        String name,

        @NotEmpty(message = "Invite at least one contact")
        @Size(max = 50, message = "A group can be created with at most 50 invitees")
        List<UUID> memberIds) {}
