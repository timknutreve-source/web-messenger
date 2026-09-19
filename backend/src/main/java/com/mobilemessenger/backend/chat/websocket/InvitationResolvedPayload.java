package com.mobilemessenger.backend.chat.websocket;

import java.util.UUID;

/**
 * Payload of the {@code INVITATION_RESOLVED} event on a user's personal
 * invitations topic: sent to both the invitee and the inviter when a contact
 * or group invitation is accepted or declined, so their other open sessions
 * drop it from "pending" and (if accepted) pick up the new contact/chat.
 * {@code kind} is {@code CONTACT} or {@code GROUP}.
 */
public record InvitationResolvedPayload(UUID invitationId, String kind, boolean accepted) {}
