import '../../contact/domain/contact_user_summary.dart';

class PollOption {
  const PollOption({required this.id, required this.text, required this.voteCount, this.voters});

  factory PollOption.fromJson(Map<String, dynamic> json) => PollOption(
        id: json['id'] as String,
        text: json['text'] as String,
        voteCount: json['voteCount'] as int,
        voters: (json['voters'] as List?)
            ?.map((e) => ContactUserSummary.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String id;
  final String text;
  final int voteCount;

  /// Who voted for this option - `null` (not an empty list) in an anonymous
  /// poll, which never reveals voters.
  final List<ContactUserSummary>? voters;
}

/// A poll attached to a group message, as the current user sees it.
class Poll {
  const Poll({
    required this.id,
    required this.messageId,
    required this.question,
    required this.anonymous,
    required this.options,
    required this.totalVotes,
    this.myOptionId,
  });

  factory Poll.fromJson(Map<String, dynamic> json) => Poll(
        id: json['id'] as String,
        messageId: json['messageId'] as String,
        question: json['question'] as String,
        anonymous: json['anonymous'] as bool,
        options: (json['options'] as List).map((e) => PollOption.fromJson(e as Map<String, dynamic>)).toList(),
        totalVotes: json['totalVotes'] as int,
        myOptionId: json['myOptionId'] as String?,
      );

  final String id;
  final String messageId;
  final String question;
  final bool anonymous;
  final List<PollOption> options;
  final int totalVotes;

  /// The option the current user voted for, or null if they haven't voted.
  final String? myOptionId;
}
