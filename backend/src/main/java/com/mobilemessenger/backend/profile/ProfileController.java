package com.mobilemessenger.backend.profile;

import com.mobilemessenger.backend.profile.dto.UpdateProfileRequest;
import com.mobilemessenger.backend.user.UserResponse;
import jakarta.validation.Valid;
import java.util.UUID;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api/profile")
public class ProfileController {

    private final ProfileService profileService;

    public ProfileController(ProfileService profileService) {
        this.profileService = profileService;
    }

    @GetMapping
    public ResponseEntity<UserResponse> getProfile(Authentication authentication) {
        return ResponseEntity.ok(profileService.getProfile(currentUserId(authentication)));
    }

    @PutMapping
    public ResponseEntity<UserResponse> updateProfile(
            Authentication authentication, @Valid @RequestBody UpdateProfileRequest request) {
        return ResponseEntity.ok(profileService.updateProfile(currentUserId(authentication), request));
    }

    @PostMapping(value = "/avatar", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<UserResponse> uploadAvatar(
            Authentication authentication, @RequestParam("file") MultipartFile file) {
        return ResponseEntity.ok(profileService.uploadAvatar(currentUserId(authentication), file));
    }

    @GetMapping("/avatar/{fileName}")
    public ResponseEntity<byte[]> getAvatar(@PathVariable String fileName) {
        ProfileService.LoadedAvatar avatar = profileService.loadAvatar(fileName);
        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_TYPE, avatar.contentType())
                .header(HttpHeaders.CACHE_CONTROL, "private, max-age=86400")
                .body(avatar.content());
    }

    private UUID currentUserId(Authentication authentication) {
        return (UUID) authentication.getPrincipal();
    }
}
