package com.mobilemessenger.backend.contact;

import com.mobilemessenger.backend.contact.dto.ContactResponse;
import com.mobilemessenger.backend.contact.dto.ContactUserSummary;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;
import org.springframework.security.core.Authentication;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/contacts")
@Validated
public class ContactController {

    private final ContactService contactService;

    public ContactController(ContactService contactService) {
        this.contactService = contactService;
    }

    @GetMapping
    public List<ContactResponse> listContacts(Authentication authentication) {
        return contactService.listContacts(currentUserId(authentication));
    }

    @GetMapping("/search")
    public List<ContactUserSummary> search(
            Authentication authentication,
            @RequestParam @Size(min = 2, message = "Search query must be at least 2 characters") String q) {
        return contactService.search(currentUserId(authentication), q);
    }

    private UUID currentUserId(Authentication authentication) {
        return (UUID) authentication.getPrincipal();
    }
}
