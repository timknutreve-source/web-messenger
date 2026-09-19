package com.mobilemessenger.backend.chat.group.dto;

import com.mobilemessenger.backend.contact.dto.ContactUserSummary;
import java.time.Instant;

public record GroupMemberResponse(ContactUserSummary user, String role, Instant joinedAt) {}
