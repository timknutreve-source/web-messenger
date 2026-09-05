package com.mobilemessenger.backend.chat.websocket;

import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.server.ServerHttpRequest;
import org.springframework.http.server.ServerHttpResponse;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.socket.WebSocketHandler;
import org.springframework.web.socket.server.HandshakeInterceptor;

/**
 * Copies the {@link Authentication} already established for the handshake
 * HTTP request (by the same {@code JwtAuthenticationFilter} used for every
 * REST call - the WebSocket handshake is itself an ordinary HTTP request
 * that passes through the full Spring Security filter chain) into the
 * WebSocket session attributes, so {@link PrincipalHandshakeHandler} can
 * turn it into the session's {@link java.security.Principal}. No second
 * authentication mechanism, no token in a STOMP frame - the same JWT bearer
 * token used for REST calls, sent as the handshake request's {@code
 * Authorization} header.
 */
public class AuthHandshakeInterceptor implements HandshakeInterceptor {

    static final String PRINCIPAL_ATTRIBUTE = "principal";

    @Override
    public boolean beforeHandshake(
            ServerHttpRequest request,
            ServerHttpResponse response,
            WebSocketHandler wsHandler,
            Map<String, Object> attributes) {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !(authentication.getPrincipal() instanceof UUID userId)) {
            response.setStatusCode(HttpStatus.UNAUTHORIZED);
            return false;
        }
        attributes.put(PRINCIPAL_ATTRIBUTE, new StompPrincipal(userId.toString()));
        return true;
    }

    @Override
    public void afterHandshake(
            ServerHttpRequest request, ServerHttpResponse response, WebSocketHandler wsHandler, Exception exception) {
        // no-op
    }
}
