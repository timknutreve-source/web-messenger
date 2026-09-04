package com.mobilemessenger.backend.contact;

import com.mobilemessenger.backend.contact.dto.ContactResponse;
import com.mobilemessenger.backend.contact.dto.ContactUserSummary;
import com.mobilemessenger.backend.user.User;
import com.mobilemessenger.backend.user.UserRepository;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;

@Service
public class ContactService {

    private static final int MAX_SEARCH_RESULTS = 20;

    private final ContactRepository contactRepository;
    private final UserRepository userRepository;

    public ContactService(ContactRepository contactRepository, UserRepository userRepository) {
        this.contactRepository = contactRepository;
        this.userRepository = userRepository;
    }

    public List<ContactUserSummary> search(UUID currentUserId, String query) {
        String trimmed = query.trim();
        return userRepository
                .searchByUsernameOrEmail(currentUserId, trimmed, PageRequest.of(0, MAX_SEARCH_RESULTS))
                .stream()
                .map(ContactUserSummary::from)
                .toList();
    }

    public boolean areContacts(UUID userId, UUID otherUserId) {
        return contactRepository.existsByUserIdAndContactId(userId, otherUserId);
    }

    /** Creates both directions of the relationship, so it's symmetric from either side. */
    public void createMutualContact(UUID userIdA, UUID userIdB) {
        if (!contactRepository.existsByUserIdAndContactId(userIdA, userIdB)) {
            contactRepository.save(new Contact(userIdA, userIdB));
        }
        if (!contactRepository.existsByUserIdAndContactId(userIdB, userIdA)) {
            contactRepository.save(new Contact(userIdB, userIdA));
        }
    }

    public List<ContactResponse> listContacts(UUID userId) {
        List<Contact> contacts = contactRepository.findByUserIdOrderByCreatedAtDesc(userId);
        if (contacts.isEmpty()) {
            return List.of();
        }

        Map<UUID, User> usersById = userRepository
                .findAllById(contacts.stream().map(Contact::getContactId).toList())
                .stream()
                .collect(Collectors.toMap(User::getId, user -> user));

        return contacts.stream()
                .map(contact -> new ContactResponse(
                        ContactUserSummary.from(usersById.get(contact.getContactId())),
                        contact.getCreatedAt()))
                .toList();
    }
}
