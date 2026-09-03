package com.mobilemessenger.backend.health;

/**
 * Response payload for the health endpoint.
 */
public record HealthStatus(String status) {

    public static HealthStatus ok() {
        return new HealthStatus("ok");
    }

    public static HealthStatus error() {
        return new HealthStatus("error");
    }
}
