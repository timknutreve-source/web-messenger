import 'message.dart';

/// The matches of a search within one chat, oldest first. [truncated] means
/// there were more matches than the server returns (only the most recent are).
class MessageSearchResult {
  const MessageSearchResult({required this.results, required this.truncated});

  factory MessageSearchResult.fromJson(Map<String, dynamic> json) => MessageSearchResult(
        results: (json['results'] as List).map((e) => Message.fromJson(e as Map<String, dynamic>)).toList(),
        truncated: json['truncated'] as bool,
      );

  final List<Message> results;
  final bool truncated;
}
