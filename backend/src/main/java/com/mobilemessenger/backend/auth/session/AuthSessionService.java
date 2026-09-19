package com.mobilemessenger.backend.auth.session;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.NoSuchElementException;
import java.util.Optional;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AuthSessionService {

    static final String DEFAULT_LABEL = "Unknown device";
    private static final int MAX_LABEL_LENGTH = 100;

    /** How stale {@code lastSeenAt} may get before a request refreshes it (avoids a write per request). */
    private static final Duration TOUCH_INTERVAL = Duration.ofMinutes(1);

    private final AuthSessionRepository repository;

    public AuthSessionService(AuthSessionRepository repository) {
        this.repository = repository;
    }

    @Transactional
    public AuthSession create(UUID userId, String deviceLabel) {
        return repository.save(new AuthSession(userId, normalizeLabel(deviceLabel)));
    }

    /**
     * Whether a token carrying this session id may still be used. A revoked
     * or unknown session (e.g. deleted along with its account) never may.
     * Refreshes {@code lastSeenAt} at most once per {@link #TOUCH_INTERVAL}.
     */
    @Transactional
    public boolean isActive(UUID sessionId) {
        Optional<AuthSession> found = repository.findById(sessionId);
        if (found.isEmpty() || found.get().isRevoked()) {
            return false;
        }
        AuthSession session = found.get();
        Instant now = Instant.now();
        if (Duration.between(session.getLastSeenAt(), now).compareTo(TOUCH_INTERVAL) > 0) {
            session.touch(now);
            repository.save(session);
        }
        return true;
    }

    /** Revokes exactly one session belonging to {@code userId}; the user's other sessions are untouched. */
    @Transactional
    public void revoke(UUID sessionId, UUID userId) {
        AuthSession session = repository.findById(sessionId)
                .filter(s -> s.getUserId().equals(userId))
                .orElseThrow(() -> new NoSuchElementException("Session not found"));
        session.revoke();
        repository.save(session);
    }

    public List<AuthSession> listActive(UUID userId) {
        return repository.findByUserIdAndRevokedAtIsNullOrderByLastSeenAtDesc(userId);
    }

    private String normalizeLabel(String label) {
        if (label == null || label.isBlank()) {
            return DEFAULT_LABEL;
        }
        String trimmed = label.trim();
        return trimmed.length() > MAX_LABEL_LENGTH ? trimmed.substring(0, MAX_LABEL_LENGTH) : trimmed;
    }
}
