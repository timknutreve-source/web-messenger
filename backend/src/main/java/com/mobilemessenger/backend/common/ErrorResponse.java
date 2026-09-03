package com.mobilemessenger.backend.common;

import com.fasterxml.jackson.annotation.JsonInclude;
import java.util.Map;

/**
 * Uniform error body returned by the API. {@code fieldErrors} is only present
 * for request validation failures.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record ErrorResponse(String error, Map<String, String> fieldErrors) {

    public ErrorResponse(String error) {
        this(error, null);
    }
}
