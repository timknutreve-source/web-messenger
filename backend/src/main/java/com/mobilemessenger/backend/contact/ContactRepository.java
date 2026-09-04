package com.mobilemessenger.backend.contact;

import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ContactRepository extends JpaRepository<Contact, UUID> {

    boolean existsByUserIdAndContactId(UUID userId, UUID contactId);

    List<Contact> findByUserIdOrderByCreatedAtDesc(UUID userId);
}
