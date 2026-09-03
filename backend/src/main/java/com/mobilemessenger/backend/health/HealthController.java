package com.mobilemessenger.backend.health;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Exposes the public health-check endpoint used by clients (e.g. the Flutter app)
 * to verify that the backend and its database connection are reachable.
 */
@RestController
public class HealthController {

    private final HealthService healthService;

    public HealthController(HealthService healthService) {
        this.healthService = healthService;
    }

    @GetMapping("/api/health")
    public ResponseEntity<HealthStatus> health() {
        if (healthService.isHealthy()) {
            return ResponseEntity.ok(HealthStatus.ok());
        }
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).body(HealthStatus.error());
    }
}
