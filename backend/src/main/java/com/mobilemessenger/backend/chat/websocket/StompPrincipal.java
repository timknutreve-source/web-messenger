package com.mobilemessenger.backend.chat.websocket;

import java.security.Principal;

/** Wraps the authenticated user's id as a {@link Principal}, as required by the STOMP session API. */
public record StompPrincipal(String name) implements Principal {

    @Override
    public String getName() {
        return name;
    }
}
