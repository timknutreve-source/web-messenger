package com.mobilemessenger.backend.user;

import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface UserRepository extends JpaRepository<User, UUID> {

    Optional<User> findByEmail(String email);

    Optional<User> findByUsernameIgnoreCase(String username);

    boolean existsByEmail(String email);

    boolean existsByUsernameIgnoreCase(String username);

    /** For profile updates: true if another user (not {@code id}) already has this email. */
    boolean existsByEmailAndIdNot(String email, UUID id);

    /** For profile updates: true if another user (not {@code id}) already has this username. */
    boolean existsByUsernameIgnoreCaseAndIdNot(String username, UUID id);
}
