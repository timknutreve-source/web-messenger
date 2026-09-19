package com.mobilemessenger.backend.auth.session;

import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface AuthSessionRepository extends JpaRepository<AuthSession, UUID> {

    List<AuthSession> findByUserIdAndRevokedAtIsNullOrderByLastSeenAtDesc(UUID userId);
}
