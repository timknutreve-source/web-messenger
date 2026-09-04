package com.mobilemessenger.backend.auth;

import com.mobilemessenger.backend.auth.dto.AuthResponse;
import com.mobilemessenger.backend.auth.dto.LoginRequest;
import com.mobilemessenger.backend.auth.dto.RegisterRequest;
import com.mobilemessenger.backend.auth.exception.InvalidCredentialsException;
import com.mobilemessenger.backend.auth.security.JwtService;
import com.mobilemessenger.backend.user.User;
import com.mobilemessenger.backend.user.UserRepository;
import com.mobilemessenger.backend.user.UserResponse;
import com.mobilemessenger.backend.user.exception.DuplicateEmailException;
import com.mobilemessenger.backend.user.exception.DuplicateUsernameException;
import java.util.Locale;
import java.util.NoSuchElementException;
import java.util.UUID;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

@Service
public class AuthService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;
    private final EmailVerificationService emailVerificationService;

    public AuthService(
            UserRepository userRepository,
            PasswordEncoder passwordEncoder,
            JwtService jwtService,
            EmailVerificationService emailVerificationService) {
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
        this.jwtService = jwtService;
        this.emailVerificationService = emailVerificationService;
    }

    public AuthResponse register(RegisterRequest request) {
        String username = request.username().trim();
        String email = normalizeEmail(request.email());

        if (userRepository.existsByEmail(email)) {
            throw new DuplicateEmailException();
        }
        if (userRepository.existsByUsernameIgnoreCase(username)) {
            throw new DuplicateUsernameException();
        }

        User user = new User(username, email, passwordEncoder.encode(request.password()));
        user = userRepository.save(user);

        // Login is not gated on verification (see README) - registering
        // still logs the user straight in - but they get a real verification
        // email straight away so they can confirm the address whenever they like.
        emailVerificationService.createAndSendVerificationToken(user);

        return new AuthResponse(jwtService.generateToken(user), UserResponse.from(user));
    }

    public AuthResponse login(LoginRequest request) {
        String identifier = request.usernameOrEmail().trim();

        User user = userRepository.findByEmail(normalizeEmail(identifier))
                .or(() -> userRepository.findByUsernameIgnoreCase(identifier))
                .orElseThrow(InvalidCredentialsException::new);

        if (!passwordEncoder.matches(request.password(), user.getPasswordHash())) {
            throw new InvalidCredentialsException();
        }

        return new AuthResponse(jwtService.generateToken(user), UserResponse.from(user));
    }

    public UserResponse getCurrentUser(UUID userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new NoSuchElementException("User not found"));
        return UserResponse.from(user);
    }

    private String normalizeEmail(String email) {
        return email.trim().toLowerCase(Locale.ROOT);
    }
}
