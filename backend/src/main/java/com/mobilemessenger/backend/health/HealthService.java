package com.mobilemessenger.backend.health;

import org.springframework.stereotype.Service;

/**
 * Business layer for determining overall application health.
 */
@Service
public class HealthService {

    private final DatabaseHealthRepository databaseHealthRepository;

    public HealthService(DatabaseHealthRepository databaseHealthRepository) {
        this.databaseHealthRepository = databaseHealthRepository;
    }

    public boolean isHealthy() {
        return databaseHealthRepository.isReachable();
    }
}
