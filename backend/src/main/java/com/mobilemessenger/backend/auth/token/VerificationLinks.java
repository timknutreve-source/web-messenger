package com.mobilemessenger.backend.auth.token;

/**
 * Builds the links embedded in verification/reset emails.
 *
 * {@code app.frontend-base-url} defaults to the app's custom URL scheme
 * ({@code mobilemessenger://}), deliberately built with a leading slash
 * before the path (giving e.g. {@code mobilemessenger:///verify-email?...})
 * so the URI parses with an empty host and {@code /verify-email} as the
 * path - which matches go_router's route path directly. A real deployment
 * can instead point this at an HTTPS app-links domain without any code change.
 */
public final class VerificationLinks {

    private VerificationLinks() {
    }

    public static String verifyEmailLink(String frontendBaseUrl, String token) {
        return frontendBaseUrl + "/verify-email?token=" + token;
    }

    public static String resetPasswordLink(String frontendBaseUrl, String token) {
        return frontendBaseUrl + "/reset-password?token=" + token;
    }
}
