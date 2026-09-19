package com.mobilemessenger.backend.auth.security;

import com.mobilemessenger.backend.common.ErrorResponse;
import com.mobilemessenger.backend.user.User;
import com.mobilemessenger.backend.user.UserRepository;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.Set;
import java.util.UUID;
import org.jspecify.annotations.NonNull;
import org.springframework.http.MediaType;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;
import tools.jackson.databind.ObjectMapper;

/**
 * Blocks an authenticated-but-unverified account from every endpoint except
 * a small allowlist (auth itself, and its own verification/resend). This is
 * the server-side backstop for "a new user cannot use the app normally
 * before verifying their email" - the Flutter app's router already redirects
 * an unverified user straight to the code-entry screen so this rarely
 * triggers in practice, but that client-side routing alone would be
 * trivially bypassed by calling the API directly, so the real enforcement
 * has to live here.
 *
 * Deliberately never touches chat/contact/profile logic itself - it runs
 * once, centrally, in the filter chain, before any of those controllers
 * ever see the request.
 */
public class EmailVerificationGateFilter extends OncePerRequestFilter {

    private static final Set<String> ALLOWED_WHILE_UNVERIFIED = Set.of(
            "/api/health",
            "/api/auth/register",
            "/api/auth/login",
            "/api/auth/me",
            "/api/auth/logout",
            "/api/auth/verify-email",
            "/api/auth/resend-verification",
            "/api/auth/forgot-password",
            "/api/auth/reset-password");

    private final UserRepository userRepository;
    private final ObjectMapper objectMapper;

    public EmailVerificationGateFilter(UserRepository userRepository, ObjectMapper objectMapper) {
        this.userRepository = userRepository;
        this.objectMapper = objectMapper;
    }

    @Override
    protected void doFilterInternal(
            @NonNull HttpServletRequest request,
            @NonNull HttpServletResponse response,
            @NonNull FilterChain filterChain) throws ServletException, IOException {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();

        if (authentication != null
                && authentication.isAuthenticated()
                && authentication.getPrincipal() instanceof UUID userId
                && !ALLOWED_WHILE_UNVERIFIED.contains(request.getRequestURI())) {
            // A missing user (e.g. deleted mid-session) is left for the
            // controller layer to report as a 404 - not this filter's concern.
            boolean verified = userRepository.findById(userId).map(User::isEmailVerified).orElse(true);
            if (!verified) {
                response.setStatus(403);
                response.setContentType(MediaType.APPLICATION_JSON_VALUE);
                response.getWriter().write(objectMapper.writeValueAsString(
                        new ErrorResponse("Please verify your email address to continue.")));
                return;
            }
        }

        filterChain.doFilter(request, response);
    }
}
