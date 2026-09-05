import 'dart:io';

import 'attachment.dart';

enum PendingAttachmentState { uploading, uploaded, failed }

/// A locally picked image/video, tracked through its upload to the server
/// before it can be attached to an outgoing message. Composing is blocked
/// on [PendingAttachmentState.uploading] (to avoid sending a message that
/// references an attachment that doesn't exist yet, and to prevent
/// duplicate uploads) and surfaces [PendingAttachmentState.failed] so the
/// user can see and retry it rather than the upload silently vanishing.
class PendingAttachment {
  const PendingAttachment({
    required this.file,
    required this.kind,
    required this.state,
    this.uploaded,
    this.error,
  });

  final File file;
  final AttachmentKind kind;
  final PendingAttachmentState state;

  /// Set once [state] is [PendingAttachmentState.uploaded].
  final Attachment? uploaded;

  /// Set once [state] is [PendingAttachmentState.failed].
  final Object? error;

  PendingAttachment copyWith({
    PendingAttachmentState? state,
    Attachment? uploaded,
    Object? error,
  }) =>
      PendingAttachment(
        file: file,
        kind: kind,
        state: state ?? this.state,
        uploaded: uploaded ?? this.uploaded,
        error: error ?? this.error,
      );
}
