package com.mobilemessenger.backend.chat;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.mobilemessenger.backend.support.ApiTestSupport;
import com.mobilemessenger.backend.support.ApiTestSupport.TestUser;
import com.mobilemessenger.backend.user.UserRepository;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.web.servlet.MockMvc;
import tools.jackson.databind.JsonNode;

/**
 * The web app reports "delivered" and "read" for a message within
 * milliseconds of each other (the chat is already open when it arrives).
 * Those two requests must never leave the message DELIVERED: read is the
 * further state, and a status must not move backwards.
 *
 * <p>Not {@code @Transactional}: the requests genuinely run concurrently on
 * separate connections, which a single test transaction would hide.
 */
@SpringBootTest
@AutoConfigureMockMvc
class MessageStatusRaceIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    private final List<UUID> createdUserIds = new ArrayList<>();

    @AfterEach
    void cleanUp() {
        userRepository.deleteAllById(createdUserIds);
    }

    @Test
    void concurrentDeliveredAndReadAlwaysEndUpRead() throws Exception {
        ApiTestSupport api = new ApiTestSupport(mockMvc, userRepository);
        TestUser alice = api.user("race_a" + UUID.randomUUID().toString().substring(0, 6));
        TestUser bob = api.user("race_b" + UUID.randomUUID().toString().substring(0, 6));
        createdUserIds.add(alice.id());
        createdUserIds.add(bob.id());
        UUID chat = api.becomeContacts(alice, bob);

        ExecutorService pool = Executors.newFixedThreadPool(8);
        try {
            for (int round = 0; round < 25; round++) {
                String messageId = api.sendMessage(alice, chat, "race " + round).get("id").asString();
                CountDownLatch go = new CountDownLatch(1);
                Future<?> delivered = pool.submit(() -> {
                    go.await();
                    api.request("POST", "/api/chats/" + chat + "/messages/" + messageId + "/delivered", bob, null)
                            .andExpect(status().isOk());
                    return null;
                });
                Future<?> read = pool.submit(() -> {
                    go.await();
                    api.request("POST", "/api/chats/" + chat + "/messages/read", bob, null)
                            .andExpect(status().isNoContent());
                    return null;
                });
                go.countDown();
                delivered.get();
                read.get();

                JsonNode page = api.json(api.request("GET", "/api/chats/" + chat + "/messages", alice, null));
                String finalStatus = null;
                for (JsonNode message : page.get("messages")) {
                    if (message.get("id").asString().equals(messageId)) {
                        finalStatus = message.get("status").asString();
                    }
                }
                assertThat(finalStatus).as("round %d", round).isEqualTo("READ");
            }
        } finally {
            pool.shutdownNow();
        }
    }
}
