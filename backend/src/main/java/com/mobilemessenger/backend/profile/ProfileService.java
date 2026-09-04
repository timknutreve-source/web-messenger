package com.mobilemessenger.backend.profile;

import com.mobilemessenger.backend.profile.dto.UpdateProfileRequest;
import com.mobilemessenger.backend.storage.FileStorageService;
import com.mobilemessenger.backend.storage.ImageValidator;
import com.mobilemessenger.backend.storage.exception.FileTooLargeException;
import com.mobilemessenger.backend.storage.exception.UnsupportedFileTypeException;
import com.mobilemessenger.backend.user.User;
import com.mobilemessenger.backend.user.UserRepository;
import com.mobilemessenger.backend.user.UserResponse;
import com.mobilemessenger.backend.user.exception.DuplicateEmailException;
import com.mobilemessenger.backend.user.exception.DuplicateUsernameException;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.Locale;
import java.util.NoSuchElementException;
import java.util.UUID;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

@Service
public class ProfileService {

    private static final String AVATAR_CATEGORY = "avatars";

    private final UserRepository userRepository;
    private final FileStorageService fileStorageService;

    public ProfileService(UserRepository userRepository, FileStorageService fileStorageService) {
        this.userRepository = userRepository;
        this.fileStorageService = fileStorageService;
    }

    public UserResponse getProfile(UUID userId) {
        return UserResponse.from(findUser(userId));
    }

    /**
     * Updates the caller's own editable profile fields. {@code userId} must
     * come from the authenticated JWT, never from client-supplied input, so
     * a user can never update another account through this method.
     */
    public UserResponse updateProfile(UUID userId, UpdateProfileRequest request) {
        User user = findUser(userId);
        String username = request.username().trim();
        String email = normalizeEmail(request.email());

        if (userRepository.existsByEmailAndIdNot(email, userId)) {
            throw new DuplicateEmailException();
        }
        if (userRepository.existsByUsernameIgnoreCaseAndIdNot(username, userId)) {
            throw new DuplicateUsernameException();
        }

        boolean emailChanged = !email.equals(user.getEmail());
        user.setUsername(username);
        user.setEmail(email);
        user.setAboutMe(normalizeAboutMe(request.aboutMe()));
        if (emailChanged) {
            // The new address hasn't been verified. Real verification-email
            // delivery is Phase 4's responsibility; this just makes sure the
            // account never appears verified for an address nobody confirmed.
            user.setEmailVerified(false);
        }

        return UserResponse.from(userRepository.save(user));
    }

    public UserResponse uploadAvatar(UUID userId, MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw new UnsupportedFileTypeException("No file was uploaded");
        }
        if (file.getSize() > ImageValidator.MAX_AVATAR_SIZE_BYTES) {
            throw new FileTooLargeException("Image exceeds the maximum size of 5MB");
        }

        byte[] content;
        try {
            content = file.getBytes();
        } catch (IOException e) {
            throw new UncheckedIOException("Failed to read uploaded file", e);
        }

        String format = ImageValidator.detectSupportedFormat(content);
        if (format == null) {
            throw new UnsupportedFileTypeException("Only JPEG and PNG images are supported");
        }

        User user = findUser(userId);
        String previousAvatarFileName = user.getAvatarFileName();

        String extension = "jpeg".equals(format) ? "jpg" : format;
        String storedFileName = fileStorageService.store(AVATAR_CATEGORY, content, extension);
        user.setAvatarFileName(storedFileName);
        UserResponse response = UserResponse.from(userRepository.save(user));

        if (previousAvatarFileName != null) {
            fileStorageService.delete(AVATAR_CATEGORY, previousAvatarFileName);
        }

        return response;
    }

    /**
     * Loads a previously uploaded avatar's raw bytes and content type.
     *
     * Any authenticated user may load any avatar by its (unguessable,
     * server-generated) file name - avatars aren't sensitive data, and later
     * phases (contacts, chat) will need users to see each other's avatars.
     */
    public LoadedAvatar loadAvatar(String storedFileName) {
        if (!fileStorageService.exists(AVATAR_CATEGORY, storedFileName)) {
            throw new NoSuchElementException("Avatar not found");
        }
        byte[] content = fileStorageService.load(AVATAR_CATEGORY, storedFileName);
        String contentType = storedFileName.toLowerCase(Locale.ROOT).endsWith(".png")
                ? MediaType.IMAGE_PNG_VALUE
                : MediaType.IMAGE_JPEG_VALUE;
        return new LoadedAvatar(content, contentType);
    }

    private User findUser(UUID userId) {
        return userRepository.findById(userId)
                .orElseThrow(() -> new NoSuchElementException("User not found"));
    }

    private String normalizeEmail(String email) {
        return email.trim().toLowerCase(Locale.ROOT);
    }

    private String normalizeAboutMe(String aboutMe) {
        if (aboutMe == null) {
            return null;
        }
        String trimmed = aboutMe.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    public record LoadedAvatar(byte[] content, String contentType) {
    }
}
