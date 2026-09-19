package com.mobilemessenger.backend.auth.security;

import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.Date;
import java.util.UUID;
import javax.crypto.SecretKey;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import com.mobilemessenger.backend.user.User;

/**
 * Issues and validates the stateless JWTs used to authenticate API requests.
 *
 * The token carries only the minimum needed to identify the caller (user id
 * and username) - never email or other account details.
 */
@Service
public class JwtService {

    static final String SESSION_CLAIM = "sid";

    private final SecretKey signingKey;
    private final Duration expiration;

    public JwtService(
            @Value("${jwt.secret}") String secret,
            @Value("${jwt.expiration-minutes}") long expirationMinutes) {
        this.signingKey = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
        this.expiration = Duration.ofMinutes(expirationMinutes);
    }

    /** Issues a token tied to {@code sessionId}, so that session can be revoked on its own. */
    public String generateToken(User user, UUID sessionId) {
        Instant now = Instant.now();
        return Jwts.builder()
                .subject(user.getId().toString())
                .claim("username", user.getUsername())
                .claim(SESSION_CLAIM, sessionId.toString())
                .issuedAt(Date.from(now))
                .expiration(Date.from(now.plus(expiration)))
                .signWith(signingKey)
                .compact();
    }

    /** A validated token's identity: the user, and the session it belongs to (null for a pre-sessions token). */
    public record TokenIdentity(UUID userId, UUID sessionId) {}

    /**
     * Parses and validates the token.
     *
     * @throws JwtException if the token is missing, malformed, expired, or has an invalid signature
     */
    public TokenIdentity parse(String token) {
        var claims = Jwts.parser()
                .verifyWith(signingKey)
                .build()
                .parseSignedClaims(token)
                .getPayload();
        String sid = claims.get(SESSION_CLAIM, String.class);
        return new TokenIdentity(UUID.fromString(claims.getSubject()), sid == null ? null : UUID.fromString(sid));
    }
}
