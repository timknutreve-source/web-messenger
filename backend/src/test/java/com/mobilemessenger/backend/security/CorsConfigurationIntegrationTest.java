package com.mobilemessenger.backend.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.mobilemessenger.backend.support.ApiTestSupport;
import com.mobilemessenger.backend.support.ApiTestSupport.TestUser;
import com.mobilemessenger.backend.user.UserRepository;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.messaging.converter.JacksonJsonMessageConverter;
import org.springframework.messaging.simp.stomp.StompSession;
import org.springframework.messaging.simp.stomp.StompSessionHandlerAdapter;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.socket.WebSocketHttpHeaders;
import org.springframework.web.socket.client.standard.StandardWebSocketClient;
import org.springframework.web.socket.messaging.WebSocketStompClient;

/**
 * A deployment lists the address its web app is served from
 * ({@code CORS_ALLOWED_ORIGINS}); only that origin may call the API from a
 * browser or open the WebSocket. (The default {@code *} is for development.)
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureMockMvc
@TestPropertySource(properties = "app.cors.allowed-origins=https://chat.example.com")
class CorsConfigurationIntegrationTest {

    private static final String ALLOWED = "https://chat.example.com";
    private static final String OTHER = "https://evil.example.org";

    @LocalServerPort
    private int port;

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    private TestUser user;
    private StompSession session;

    @AfterEach
    void cleanUp() {
        if (session != null && session.isConnected()) {
            session.disconnect();
        }
        if (user != null) {
            userRepository.deleteById(user.id());
        }
    }

    @Test
    void theConfiguredOriginPassesThePreflightCheck() throws Exception {
        mockMvc.perform(options("/api/auth/login")
                        .header("Origin", ALLOWED)
                        .header("Access-Control-Request-Method", "POST")
                        .header("Access-Control-Request-Headers", "authorization,content-type"))
                .andExpect(status().isOk())
                .andExpect(header().string("Access-Control-Allow-Origin", ALLOWED));
    }

    @Test
    void anyOtherOriginIsRejected() throws Exception {
        mockMvc.perform(options("/api/auth/login")
                        .header("Origin", OTHER)
                        .header("Access-Control-Request-Method", "POST"))
                .andExpect(status().isForbidden());
    }

    @Test
    void theWebSocketHandshakeAcceptsOnlyTheConfiguredOrigin() throws Exception {
        user = new ApiTestSupport(mockMvc, userRepository).user("cors" + Long.toString(System.nanoTime(), 36));

        WebSocketHttpHeaders allowed = new WebSocketHttpHeaders();
        allowed.setOrigin(ALLOWED);
        session = client().connectAsync(url(user), allowed, new StompSessionHandlerAdapter() {}).get(5, TimeUnit.SECONDS);
        assertThat(session.isConnected()).isTrue();

        WebSocketHttpHeaders other = new WebSocketHttpHeaders();
        other.setOrigin(OTHER);
        assertThrows(Exception.class, () -> client()
                .connectAsync(url(user), other, new StompSessionHandlerAdapter() {})
                .get(5, TimeUnit.SECONDS));
    }

    private String url(TestUser who) {
        return "ws://localhost:" + port + "/ws?access_token=" + who.token();
    }

    private WebSocketStompClient client() {
        WebSocketStompClient client = new WebSocketStompClient(new StandardWebSocketClient());
        client.setMessageConverter(new JacksonJsonMessageConverter());
        return client;
    }
}
