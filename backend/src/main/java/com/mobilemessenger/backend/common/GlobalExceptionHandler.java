package com.mobilemessenger.backend.common;

import com.mobilemessenger.backend.auth.exception.EmailAlreadyVerifiedException;
import com.mobilemessenger.backend.auth.exception.InvalidCredentialsException;
import com.mobilemessenger.backend.auth.exception.InvalidOrExpiredTokenException;
import com.mobilemessenger.backend.chat.exception.CannotActOnOwnMessageException;
import com.mobilemessenger.backend.chat.group.InvalidGroupOperationException;
import com.mobilemessenger.backend.chat.poll.InvalidPollException;
import com.mobilemessenger.backend.chat.exception.InvalidAttachmentException;
import com.mobilemessenger.backend.chat.exception.InvalidMessageContentException;
import com.mobilemessenger.backend.chat.exception.InvalidSearchQueryException;
import com.mobilemessenger.backend.chat.exception.MessageAlreadyDeletedException;
import com.mobilemessenger.backend.chat.exception.NotMessageSenderException;
import com.mobilemessenger.backend.contact.exception.AlreadyContactsException;
import com.mobilemessenger.backend.contact.exception.DuplicateInvitationException;
import com.mobilemessenger.backend.contact.exception.InvitationAlreadyProcessedException;
import com.mobilemessenger.backend.contact.exception.NotInvitationRecipientException;
import com.mobilemessenger.backend.contact.exception.PendingInvitationFromRecipientException;
import com.mobilemessenger.backend.contact.exception.SelfInvitationException;
import com.mobilemessenger.backend.security.encryption.exception.EncryptionException;
import com.mobilemessenger.backend.storage.exception.FileTooLargeException;
import com.mobilemessenger.backend.storage.exception.UnsupportedFileTypeException;
import com.mobilemessenger.backend.user.exception.DuplicateEmailException;
import com.mobilemessenger.backend.user.exception.DuplicateUsernameException;
import jakarta.validation.ConstraintViolationException;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.NoSuchElementException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.orm.jpa.JpaSystemException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.multipart.MaxUploadSizeExceededException;

@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorResponse> handleValidation(MethodArgumentNotValidException ex) {
        Map<String, String> fieldErrors = new LinkedHashMap<>();
        ex.getBindingResult().getFieldErrors().forEach(fieldError ->
                fieldErrors.putIfAbsent(fieldError.getField(), fieldError.getDefaultMessage()));
        return ResponseEntity.badRequest().body(new ErrorResponse("Validation failed", fieldErrors));
    }

    @ExceptionHandler(ConstraintViolationException.class)
    public ResponseEntity<ErrorResponse> handleConstraintViolation(ConstraintViolationException ex) {
        Map<String, String> fieldErrors = new LinkedHashMap<>();
        ex.getConstraintViolations().forEach(violation -> {
            String path = violation.getPropertyPath().toString();
            String field = path.contains(".") ? path.substring(path.lastIndexOf('.') + 1) : path;
            fieldErrors.putIfAbsent(field, violation.getMessage());
        });
        return ResponseEntity.badRequest().body(new ErrorResponse("Validation failed", fieldErrors));
    }

    @ExceptionHandler(DuplicateEmailException.class)
    public ResponseEntity<ErrorResponse> handleDuplicateEmail(DuplicateEmailException ex) {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(new ErrorResponse(ex.getMessage()));
    }

    @ExceptionHandler(DuplicateUsernameException.class)
    public ResponseEntity<ErrorResponse> handleDuplicateUsername(DuplicateUsernameException ex) {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(new ErrorResponse(ex.getMessage()));
    }

    @ExceptionHandler(InvalidCredentialsException.class)
    public ResponseEntity<ErrorResponse> handleInvalidCredentials(InvalidCredentialsException ex) {
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(new ErrorResponse(ex.getMessage()));
    }

    @ExceptionHandler(InvalidOrExpiredTokenException.class)
    public ResponseEntity<ErrorResponse> handleInvalidOrExpiredToken(InvalidOrExpiredTokenException ex) {
        return ResponseEntity.badRequest().body(new ErrorResponse(ex.getMessage()));
    }

    @ExceptionHandler(EmailAlreadyVerifiedException.class)
    public ResponseEntity<ErrorResponse> handleEmailAlreadyVerified(EmailAlreadyVerifiedException ex) {
        return ResponseEntity.badRequest().body(new ErrorResponse(ex.getMessage()));
    }

    @ExceptionHandler(InvalidSearchQueryException.class)
    public ResponseEntity<ErrorResponse> handleInvalidSearchQuery(InvalidSearchQueryException ex) {
        return ResponseEntity.badRequest().body(new ErrorResponse(ex.getMessage()));
    }

    @ExceptionHandler(InvalidPollException.class)
    public ResponseEntity<ErrorResponse> handleInvalidPoll(InvalidPollException ex) {
        return ResponseEntity.badRequest().body(new ErrorResponse(ex.getMessage()));
    }

    @ExceptionHandler(InvalidGroupOperationException.class)
    public ResponseEntity<ErrorResponse> handleInvalidGroupOperation(InvalidGroupOperationException ex) {
        return ResponseEntity.badRequest().body(new ErrorResponse(ex.getMessage()));
    }

    @ExceptionHandler(SelfInvitationException.class)
    public ResponseEntity<ErrorResponse> handleSelfInvitation(SelfInvitationException ex) {
        return ResponseEntity.badRequest().body(new ErrorResponse(ex.getMessage()));
    }

    @ExceptionHandler(DuplicateInvitationException.class)
    public ResponseEntity<ErrorResponse> handleDuplicateInvitation(DuplicateInvitationException ex) {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(new ErrorResponse(ex.getMessage()));
    }

    @ExceptionHandler(PendingInvitationFromRecipientException.class)
    public ResponseEntity<ErrorResponse> handlePendingInvitationFromRecipient(PendingInvitationFromRecipientException ex) {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(new ErrorResponse(ex.getMessage()));
    }

    @ExceptionHandler(AlreadyContactsException.class)
    public ResponseEntity<ErrorResponse> handleAlreadyContacts(AlreadyContactsException ex) {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(new ErrorResponse(ex.getMessage()));
    }

    @ExceptionHandler(NotInvitationRecipientException.class)
    public ResponseEntity<ErrorResponse> handleNotInvitationRecipient(NotInvitationRecipientException ex) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(new ErrorResponse(ex.getMessage()));
    }

    @ExceptionHandler(InvitationAlreadyProcessedException.class)
    public ResponseEntity<ErrorResponse> handleInvitationAlreadyProcessed(InvitationAlreadyProcessedException ex) {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(new ErrorResponse(ex.getMessage()));
    }

    @ExceptionHandler(NotMessageSenderException.class)
    public ResponseEntity<ErrorResponse> handleNotMessageSender(NotMessageSenderException ex) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(new ErrorResponse(ex.getMessage()));
    }

    @ExceptionHandler(MessageAlreadyDeletedException.class)
    public ResponseEntity<ErrorResponse> handleMessageAlreadyDeleted(MessageAlreadyDeletedException ex) {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(new ErrorResponse(ex.getMessage()));
    }

    @ExceptionHandler(CannotActOnOwnMessageException.class)
    public ResponseEntity<ErrorResponse> handleCannotActOnOwnMessage(CannotActOnOwnMessageException ex) {
        return ResponseEntity.badRequest().body(new ErrorResponse(ex.getMessage()));
    }

    @ExceptionHandler(InvalidMessageContentException.class)
    public ResponseEntity<ErrorResponse> handleInvalidMessageContent(InvalidMessageContentException ex) {
        return ResponseEntity.badRequest().body(new ErrorResponse(ex.getMessage()));
    }

    @ExceptionHandler(InvalidAttachmentException.class)
    public ResponseEntity<ErrorResponse> handleInvalidAttachment(InvalidAttachmentException ex) {
        return ResponseEntity.badRequest().body(new ErrorResponse(ex.getMessage()));
    }

    @ExceptionHandler(UnsupportedFileTypeException.class)
    public ResponseEntity<ErrorResponse> handleUnsupportedFileType(UnsupportedFileTypeException ex) {
        return ResponseEntity.badRequest().body(new ErrorResponse(ex.getMessage()));
    }

    @ExceptionHandler(EncryptionException.class)
    public ResponseEntity<ErrorResponse> handleEncryptionFailure(EncryptionException ex) {
        // Never include the exception message here: it never contains
        // plaintext or key material by construction, but a generic response
        // is still the safest default for a failure class that always
        // indicates either corrupted/tampered data or a server
        // misconfiguration - never something the caller can fix.
        log.error("Encryption/decryption failure: {}", ex.getMessage());
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(new ErrorResponse("Unable to process encrypted data"));
    }

    /**
     * {@link com.mobilemessenger.backend.security.encryption.EncryptedStringConverter} runs inside Hibernate's entity
     * hydration, so a {@link EncryptionException} it throws while reading a
     * corrupted/tampered column reaches this handler already wrapped in a
     * {@link JpaSystemException} rather than as itself - unwrap the cause
     * chain to recognize that case and still respond with the same safe,
     * generic message (never leaking that it was specifically a decryption
     * failure at the persistence layer, and never falling through to the
     * unrelated "unexpected error" wording used for other persistence bugs).
     */
    @ExceptionHandler(JpaSystemException.class)
    public ResponseEntity<ErrorResponse> handleJpaSystemException(JpaSystemException ex) {
        for (Throwable cause = ex; cause != null; cause = cause.getCause()) {
            if (cause instanceof EncryptionException) {
                log.error("Encryption/decryption failure during persistence: {}", cause.getMessage());
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(new ErrorResponse("Unable to process encrypted data"));
            }
        }
        log.error("Unexpected persistence error", ex);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(new ErrorResponse("An unexpected error occurred"));
    }

    @ExceptionHandler(FileTooLargeException.class)
    public ResponseEntity<ErrorResponse> handleFileTooLarge(FileTooLargeException ex) {
        return ResponseEntity.status(HttpStatus.PAYLOAD_TOO_LARGE).body(new ErrorResponse(ex.getMessage()));
    }

    @ExceptionHandler(MaxUploadSizeExceededException.class)
    public ResponseEntity<ErrorResponse> handleMaxUploadSizeExceeded(MaxUploadSizeExceededException ex) {
        return ResponseEntity.status(HttpStatus.PAYLOAD_TOO_LARGE)
                .body(new ErrorResponse("The uploaded file exceeds the maximum allowed request size"));
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ErrorResponse> handleIllegalArgument(IllegalArgumentException ex) {
        return ResponseEntity.badRequest().body(new ErrorResponse("Invalid request"));
    }

    @ExceptionHandler(NoSuchElementException.class)
    public ResponseEntity<ErrorResponse> handleNotFound(NoSuchElementException ex) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(new ErrorResponse(ex.getMessage()));
    }

    @ExceptionHandler(DataIntegrityViolationException.class)
    public ResponseEntity<ErrorResponse> handleDataIntegrityViolation(DataIntegrityViolationException ex) {
        log.warn("Data integrity violation: {}", ex.getMessage());
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(new ErrorResponse("This account already exists"));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleUnexpected(Exception ex) {
        log.error("Unexpected error handling request", ex);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(new ErrorResponse("An unexpected error occurred"));
    }
}
