package com.mobilemessenger.backend.chat.websocket;

import java.security.Principal;
import java.util.Map;
import org.springframework.http.server.ServerHttpRequest;
import org.springframework.web.socket.WebSocketHandler;
import org.springframework.web.socket.server.support.DefaultHandshakeHandler;

/** Turns the {@link StompPrincipal} stashed by {@link AuthHandshakeInterceptor} into the session's user. */
public class PrincipalHandshakeHandler extends DefaultHandshakeHandler {

    @Override
    protected Principal determineUser(
            ServerHttpRequest request, WebSocketHandler wsHandler, Map<String, Object> attributes) {
        Object principal = attributes.get(AuthHandshakeInterceptor.PRINCIPAL_ATTRIBUTE);
        return principal instanceof Principal p ? p : null;
    }
}
