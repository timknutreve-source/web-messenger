package com.mobilemessenger.backend.auth;

import com.mobilemessenger.backend.auth.dto.SessionResponse;
import com.mobilemessenger.backend.auth.session.AuthSessionService;
import java.util.List;
import java.util.UUID;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Selective logout: every operation here acts on individual sessions of the
 * caller's own account, so signing out of one device never signs out another.
 */
@RestController
@RequestMapping("/api/auth")
public class AuthSessionController {

    private final AuthSessionService sessionService;

    public AuthSessionController(AuthSessionService sessionService) {
        this.sessionService = sessionService;
    }

    /** Signs out the session the request was made with - and only that one. */
    @PostMapping("/logout")
    public ResponseEntity<Void> logout(Authentication authentication) {
        UUID sessionId = currentSessionId(authentication);
        if (sessionId != null) {
            sessionService.revoke(sessionId, userId(authentication));
        }
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/sessions")
    public List<SessionResponse> sessions(Authentication authentication) {
        UUID currentSessionId = currentSessionId(authentication);
        return sessionService.listActive(userId(authentication)).stream()
                .map(session -> SessionResponse.from(session, currentSessionId))
                .toList();
    }

    /** Signs out a specific other session of the caller's own account (e.g. a lost phone). */
    @DeleteMapping("/sessions/{sessionId}")
    public ResponseEntity<Void> revokeSession(Authentication authentication, @PathVariable UUID sessionId) {
        sessionService.revoke(sessionId, userId(authentication));
        return ResponseEntity.noContent().build();
    }

    private UUID userId(Authentication authentication) {
        return (UUID) authentication.getPrincipal();
    }

    /** {@code null} for a token issued before sessions existed (it carries no session id). */
    private UUID currentSessionId(Authentication authentication) {
        return authentication.getDetails() instanceof UUID sessionId ? sessionId : null;
    }
}
