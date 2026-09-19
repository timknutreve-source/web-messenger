package com.mobilemessenger.backend.chat.websocket;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.messaging.simp.config.ChannelRegistration;
import org.springframework.messaging.simp.config.MessageBrokerRegistry;
import org.springframework.web.socket.config.annotation.EnableWebSocketMessageBroker;
import org.springframework.web.socket.config.annotation.StompEndpointRegistry;
import org.springframework.web.socket.config.annotation.WebSocketMessageBrokerConfigurer;

/**
 * STOMP-over-WebSocket setup. Clients connect to {@code /ws} (authenticated
 * via the same JWT bearer token as REST calls, see {@link
 * AuthHandshakeInterceptor}), subscribe to {@code /topic/chats/{chatId}} for
 * that conversation's events (new/updated/deleted messages, status changes,
 * typing) or to their own {@code /topic/users/{userId}/invitations} for new
 * incoming contact invitations (see {@link ChatSubscriptionInterceptor} for
 * both topics' authorization checks), and send typing events to {@code
 * /app/chats/{chatId}/typing} (see {@code ChatWebSocketController}).
 */
@Configuration
@EnableWebSocketMessageBroker
public class WebSocketConfig implements WebSocketMessageBrokerConfigurer {

    private final ChatSubscriptionInterceptor chatSubscriptionInterceptor;
    private final String[] allowedOrigins;

    public WebSocketConfig(
            ChatSubscriptionInterceptor chatSubscriptionInterceptor,
            @Value("${app.cors.allowed-origins:*}") String[] allowedOrigins) {
        this.chatSubscriptionInterceptor = chatSubscriptionInterceptor;
        this.allowedOrigins = allowedOrigins;
    }

    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        registry.addEndpoint("/ws")
                .setAllowedOriginPatterns(allowedOrigins)
                .setHandshakeHandler(new PrincipalHandshakeHandler())
                .addInterceptors(new AuthHandshakeInterceptor());
    }

    @Override
    public void configureMessageBroker(MessageBrokerRegistry registry) {
        registry.enableSimpleBroker("/topic");
        registry.setApplicationDestinationPrefixes("/app");
    }

    @Override
    public void configureClientInboundChannel(ChannelRegistration registration) {
        registration.interceptors(chatSubscriptionInterceptor);
    }
}
