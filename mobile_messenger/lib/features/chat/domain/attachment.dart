enum AttachmentKind { image, video }

AttachmentKind _attachmentKindFromJson(String value) =>
    value == 'VIDEO' ? AttachmentKind.video : AttachmentKind.image;

/// A previously uploaded image/video attached to a message. [url]/[thumbnailUrl]
/// are authenticated backend paths (see [attachmentAuthHeaders]), never a raw
/// storage location.
class Attachment {
  const Attachment({
    required this.id,
    required this.type,
    required this.mimeType,
    required this.fileSize,
    this.width,
    this.height,
    this.durationSeconds,
    required this.url,
    this.thumbnailUrl,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
        id: json['id'] as String,
        type: _attachmentKindFromJson(json['type'] as String),
        mimeType: json['mimeType'] as String,
        fileSize: json['fileSize'] as int,
        width: json['width'] as int?,
        height: json['height'] as int?,
        durationSeconds: json['durationSeconds'] as int?,
        url: json['url'] as String,
        thumbnailUrl: json['thumbnailUrl'] as String?,
      );

  final String id;
  final AttachmentKind type;
  final String mimeType;
  final int fileSize;
  final int? width;
  final int? height;
  final int? durationSeconds;
  final String url;
  final String? thumbnailUrl;
}
