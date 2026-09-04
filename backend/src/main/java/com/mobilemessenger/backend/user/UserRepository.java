package com.mobilemessenger.backend.user;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface UserRepository extends JpaRepository<User, UUID> {

    Optional<User> findByEmail(String email);

    Optional<User> findByUsernameIgnoreCase(String username);

    boolean existsByEmail(String email);

    boolean existsByUsernameIgnoreCase(String username);

    /** For profile updates: true if another user (not {@code id}) already has this email. */
    boolean existsByEmailAndIdNot(String email, UUID id);

    /** For profile updates: true if another user (not {@code id}) already has this username. */
    boolean existsByUsernameIgnoreCaseAndIdNot(String username, UUID id);

    /** For contact search: case-insensitive partial match on username or email, excluding the searcher. */
    @Query("SELECT u FROM User u WHERE u.id <> :excludeUserId AND ("
            + "LOWER(u.username) LIKE LOWER(CONCAT('%', :query, '%')) "
            + "OR LOWER(u.email) LIKE LOWER(CONCAT('%', :query, '%'))) "
            + "ORDER BY u.username")
    List<User> searchByUsernameOrEmail(
            @Param("excludeUserId") UUID excludeUserId, @Param("query") String query, Pageable pageable);
}
