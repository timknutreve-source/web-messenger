package com.mobilemessenger.backend.contact.exception;

/**
 * Thrown when a user tries to send an invitation to someone who has already
 * sent *them* a pending invitation. This must never be silently turned into
 * an acceptance - only the recipient explicitly accepting/declining an
 * invitation may create a contact relationship - so the sender is told to
 * respond to the existing invitation instead of creating a redundant one.
 */
public class PendingInvitationFromRecipientException extends RuntimeException {

    public PendingInvitationFromRecipientException() {
        super("This user has already sent you an invitation - check your pending invitations");
    }
}
