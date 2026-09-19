package com.mobilemessenger.backend.auth.security;

import com.mobilemessenger.backend.auth.session.AuthSessionService;
import io.jsonwebtoken.JwtException;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.List;
import java.util.UUID;
import org.jspecify.annotations.NonNull;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Authenticates requests carrying a {@code Authorization: Bearer <token>} header.
 *
 * On a missing or invalid token this simply leaves the request unauthenticated
 * rather than rejecting it outright - {@link SecurityConfig} is what decides
 * which endpoints require authentication.
 */
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(JwtAuthenticationFilter.class);
    private static final String BEARER_PREFIX = "Bearer ";

    private static final String WEBSOCKET_PATH = "/ws";
    private static final String TOKEN_QUERY_PARAM = "access_token";

    private final JwtService jwtService;
    private final AuthSessionService sessionService;

    public JwtAuthenticationFilter(JwtService jwtService, AuthSessionService sessionService) {
        this.jwtService = jwtService;
        this.sessionService = sessionService;
    }

    @Override
    protected void doFilterInternal(
            @NonNull HttpServletRequest request,
            @NonNull HttpServletResponse response,
            @NonNull FilterChain filterChain) throws ServletException, IOException {
        String token = resolveToken(request);
        if (token != null) {
            try {
                JwtService.TokenIdentity identity = jwtService.parse(token);
                // A token tied to a session is only valid while that session
                // is (i.e. hasn't been signed out). One issued before sessions
                // existed has no session id and keeps working until it expires.
                if (identity.sessionId() == null || sessionService.isActive(identity.sessionId())) {
                    var authentication = new UsernamePasswordAuthenticationToken(identity.userId(), null, List.of());
                    authentication.setDetails(identity.sessionId());
                    SecurityContextHolder.getContext().setAuthentication(authentication);
                } else {
                    log.debug("Rejected token for a revoked or unknown session");
                    SecurityContextHolder.clearContext();
                }
            } catch (JwtException | IllegalArgumentException e) {
                log.debug("Rejected invalid JWT: {}", e.getMessage());
                SecurityContextHolder.clearContext();
            }
        }

        filterChain.doFilter(request, response);
    }

    /**
     * The bearer token from the Authorization header. A browser WebSocket
     * cannot send request headers, so for the {@code /ws} handshake - and only
     * there - the same token is also accepted as an {@code access_token}
     * query parameter. It is never honored on any other path, so a token
     * copied into an ordinary URL cannot be used to call the REST API.
     */
    private String resolveToken(HttpServletRequest request) {
        String header = request.getHeader("Authorization");
        if (header != null && header.startsWith(BEARER_PREFIX)) {
            return header.substring(BEARER_PREFIX.length());
        }
        if (WEBSOCKET_PATH.equals(request.getRequestURI())) {
            String param = request.getParameter(TOKEN_QUERY_PARAM);
            if (param != null && !param.isBlank()) {
                return param;
            }
        }
        return null;
    }
}
