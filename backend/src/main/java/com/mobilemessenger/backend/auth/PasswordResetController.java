package com.mobilemessenger.backend.auth;

import com.mobilemessenger.backend.auth.dto.ForgotPasswordRequest;
import com.mobilemessenger.backend.auth.dto.ResetPasswordRequest;
import com.mobilemessenger.backend.common.MessageResponse;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/auth")
public class PasswordResetController {

    private static final MessageResponse GENERIC_FORGOT_PASSWORD_RESPONSE =
            new MessageResponse("If that email is registered, password reset instructions have been sent.");

    private final PasswordResetService passwordResetService;

    public PasswordResetController(PasswordResetService passwordResetService) {
        this.passwordResetService = passwordResetService;
    }

    @PostMapping("/forgot-password")
    public ResponseEntity<MessageResponse> forgotPassword(@Valid @RequestBody ForgotPasswordRequest request) {
        // Always the same response/status regardless of whether the email is
        // registered - requestPasswordReset() itself is a silent no-op for
        // an unknown address, so there is nothing to branch on here.
        passwordResetService.requestPasswordReset(request.email());
        return ResponseEntity.ok(GENERIC_FORGOT_PASSWORD_RESPONSE);
    }

    @PostMapping("/reset-password")
    public ResponseEntity<MessageResponse> resetPassword(@Valid @RequestBody ResetPasswordRequest request) {
        passwordResetService.resetPassword(request.email(), request.code(), request.newPassword());
        return ResponseEntity.ok(new MessageResponse("Your password has been reset. You can now log in."));
    }
}
