package com.mobilemessenger.backend.auth;

import com.mobilemessenger.backend.auth.dto.VerifyEmailRequest;
import com.mobilemessenger.backend.common.MessageResponse;
import jakarta.validation.Valid;
import java.util.UUID;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/auth")
public class EmailVerificationController {

    private final EmailVerificationService verificationService;

    public EmailVerificationController(EmailVerificationService verificationService) {
        this.verificationService = verificationService;
    }

    @PostMapping("/verify-email")
    public ResponseEntity<MessageResponse> verifyEmail(@Valid @RequestBody VerifyEmailRequest request) {
        verificationService.verifyEmail(request.token());
        return ResponseEntity.ok(new MessageResponse("Your email has been verified."));
    }

    @PostMapping("/resend-verification")
    public ResponseEntity<MessageResponse> resendVerification(Authentication authentication) {
        UUID userId = (UUID) authentication.getPrincipal();
        verificationService.resendVerification(userId);
        return ResponseEntity.ok(new MessageResponse("Verification email sent."));
    }
}
