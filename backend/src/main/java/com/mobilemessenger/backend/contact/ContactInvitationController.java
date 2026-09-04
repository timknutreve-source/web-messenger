package com.mobilemessenger.backend.contact;

import com.mobilemessenger.backend.contact.dto.ContactInvitationResponse;
import com.mobilemessenger.backend.contact.dto.PendingInvitationResponse;
import com.mobilemessenger.backend.contact.dto.SendInvitationRequest;
import jakarta.validation.Valid;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/contacts/invitations")
public class ContactInvitationController {

    private final ContactInvitationService invitationService;

    public ContactInvitationController(ContactInvitationService invitationService) {
        this.invitationService = invitationService;
    }

    @PostMapping
    public ResponseEntity<ContactInvitationResponse> send(
            Authentication authentication, @Valid @RequestBody SendInvitationRequest request) {
        ContactInvitationResponse response =
                invitationService.sendInvitation(currentUserId(authentication), request.recipientId());
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @GetMapping("/pending")
    public List<PendingInvitationResponse> pending(Authentication authentication) {
        return invitationService.listPendingInvitations(currentUserId(authentication));
    }

    @PostMapping("/{id}/accept")
    public ContactInvitationResponse accept(Authentication authentication, @PathVariable UUID id) {
        return invitationService.acceptInvitation(id, currentUserId(authentication));
    }

    @PostMapping("/{id}/decline")
    public ContactInvitationResponse decline(Authentication authentication, @PathVariable UUID id) {
        return invitationService.declineInvitation(id, currentUserId(authentication));
    }

    private UUID currentUserId(Authentication authentication) {
        return (UUID) authentication.getPrincipal();
    }
}
