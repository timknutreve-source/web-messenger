package com.mobilemessenger.backend.chat.group.dto;

import com.mobilemessenger.backend.contact.dto.ContactUserSummary;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

/** A group with its current members and the people invited but who haven't answered yet. */
public record GroupDetailsResponse(
        UUID id,
        String name,
        UUID createdBy,
        Instant createdAt,
        List<GroupMemberResponse> members,
        List<ContactUserSummary> pendingInvitees) {}
