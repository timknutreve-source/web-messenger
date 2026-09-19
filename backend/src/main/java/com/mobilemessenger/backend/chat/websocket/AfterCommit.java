package com.mobilemessenger.backend.chat.websocket;

import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * Runs an action once the surrounding transaction has committed (or right
 * away when there is none). Used for WebSocket events that tell clients to
 * refetch: sent from inside the transaction, a fast client could refetch
 * before the change is visible and see stale data.
 */
public final class AfterCommit {

    private AfterCommit() {}

    public static void run(Runnable action) {
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            action.run();
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                action.run();
            }
        });
    }
}
