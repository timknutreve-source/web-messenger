/// Client-side validation for profile-editing fields not already covered by
/// [AuthValidators] (username/email are reused as-is from the auth feature,
/// since the rules are identical).
class ProfileValidators {
  const ProfileValidators._();

  static const aboutMeMaxLength = 500;
  static const maxImageSizeBytes = 5 * 1024 * 1024;
  static const allowedImageExtensions = {'jpg', 'jpeg', 'png'};

  static String? aboutMe(String? value) {
    if (value != null && value.length > aboutMeMaxLength) {
      return 'About Me must be at most $aboutMeMaxLength characters';
    }
    return null;
  }

  /// Validates a picked image's file extension and size before it's ever
  /// uploaded, mirroring the backend's rules for fast, offline feedback.
  /// The backend re-validates the actual file content regardless.
  static String? pickedImage({required String fileExtension, required int sizeBytes}) {
    if (!allowedImageExtensions.contains(fileExtension.toLowerCase())) {
      return 'Only JPEG and PNG images are supported.';
    }
    if (sizeBytes > maxImageSizeBytes) {
      return 'Image must be 5MB or smaller.';
    }
    return null;
  }
}
