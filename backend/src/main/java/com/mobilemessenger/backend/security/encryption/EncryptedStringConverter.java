package com.mobilemessenger.backend.security.encryption;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;
import org.springframework.stereotype.Component;

/**
 * Transparently encrypts a {@code String} entity attribute before it is
 * written to its database column, and decrypts it when the column is read
 * back - applied explicitly per-field (see {@code @Convert} on {@code
 * Message.content}, {@code User.aboutMe}, {@code
 * MessageAttachment.originalFilename}), never {@code autoApply}, so no
 * column is encrypted without a deliberate decision.
 *
 * <p>Because this stays entirely inside the entity <-> column boundary, no
 * service or controller code needs to know encryption is happening at all:
 * {@code message.getContent()} already returns plaintext.
 *
 * <p>JPA instantiates {@code AttributeConverter}s itself (not via the
 * Spring container), so the {@link EncryptionService} dependency is wired
 * through a static holder set by {@link Initializer} at application
 * startup, rather than constructor injection.
 */
@Converter
public class EncryptedStringConverter implements AttributeConverter<String, String> {

    private static volatile EncryptionService encryptionService;

    @Override
    public String convertToDatabaseColumn(String attribute) {
        if (attribute == null) {
            return null;
        }
        return requireService().encrypt(attribute);
    }

    @Override
    public String convertToEntityAttribute(String dbData) {
        if (dbData == null) {
            return null;
        }
        return requireService().decrypt(dbData);
    }

    private static EncryptionService requireService() {
        EncryptionService service = encryptionService;
        if (service == null) {
            throw new IllegalStateException(
                    "EncryptedStringConverter used before the Spring application context initialized "
                            + "EncryptionService");
        }
        return service;
    }

    /** Publishes the Spring-managed {@link EncryptionService} to the static holder above. */
    @Component
    static class Initializer {
        Initializer(EncryptionService encryptionService) {
            EncryptedStringConverter.encryptionService = encryptionService;
        }
    }
}
