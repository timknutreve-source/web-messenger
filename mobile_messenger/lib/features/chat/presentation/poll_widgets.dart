import 'package:flutter/material.dart';

import '../domain/poll.dart';
import 'widgets/highlighted_text.dart';

/// A poll inside a message bubble: the question, each option as a tappable
/// row with its share of the votes, and - for a public poll - who voted.
///
/// Tapping an option votes for it (or moves the user's vote there); tapping
/// the option already chosen, or "Retract vote", takes the vote back.
class PollBubbleContent extends StatelessWidget {
  const PollBubbleContent({
    super.key,
    required this.poll,
    required this.onVote,
    required this.onRetract,
    this.highlight,
  });

  final Poll poll;
  final void Function(String optionId) onVote;
  final VoidCallback onRetract;
  final String? highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasVoted = poll.myOptionId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.poll_outlined, size: 16, color: colors.primary),
            const SizedBox(width: 4),
            Text(
              poll.anonymous ? 'Anonymous poll' : 'Public poll',
              key: const Key('poll_kind_label'),
              style: theme.textTheme.labelSmall?.copyWith(color: colors.primary),
            ),
          ],
        ),
        const SizedBox(height: 4),
        HighlightedText(poll.question, query: highlight, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final option in poll.options)
          _PollOptionRow(
            key: Key('poll_option_${option.id}'),
            option: option,
            totalVotes: poll.totalVotes,
            selected: option.id == poll.myOptionId,
            showVoters: !poll.anonymous,
            onTap: () => option.id == poll.myOptionId ? onRetract() : onVote(option.id),
          ),
        Row(
          children: [
            Text(
              poll.totalVotes == 1 ? '1 vote' : '${poll.totalVotes} votes',
              key: const Key('poll_total_votes'),
              style: theme.textTheme.labelSmall,
            ),
            const Spacer(),
            if (hasVoted)
              TextButton(
                key: const Key('poll_retract_button'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: onRetract,
                child: const Text('Retract vote'),
              ),
          ],
        ),
      ],
    );
  }
}

class _PollOptionRow extends StatelessWidget {
  const _PollOptionRow({
    super.key,
    required this.option,
    required this.totalVotes,
    required this.selected,
    required this.showVoters,
    required this.onTap,
  });

  final PollOption option;
  final int totalVotes;
  final bool selected;
  final bool showVoters;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final fraction = totalVotes == 0 ? 0.0 : option.voteCount / totalVotes;
    final voters = option.voters;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        button: true,
        selected: selected,
        label: '${option.text}, ${option.voteCount} ${option.voteCount == 1 ? 'vote' : 'votes'}'
            '${selected ? ', your vote' : ''}',
        excludeSemantics: true,
        onTap: onTap,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: selected ? colors.primary : colors.outlineVariant, width: selected ? 2 : 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      selected ? Icons.check_circle : Icons.radio_button_unchecked,
                      key: Key(selected ? 'poll_option_selected_icon' : 'poll_option_unselected_icon'),
                      size: 18,
                      color: selected ? colors.primary : colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(option.text)),
                    const SizedBox(width: 8),
                    Text(
                      '${option.voteCount}',
                      key: Key('poll_option_count_${option.id}'),
                      style: theme.textTheme.labelMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(value: fraction, minHeight: 4, borderRadius: BorderRadius.circular(2)),
                if (showVoters && voters != null && voters.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      voters.map((v) => v.username).join(', '),
                      key: Key('poll_option_voters_${option.id}'),
                      style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The values collected by [CreatePollDialog].
class NewPoll {
  const NewPoll({required this.question, required this.options, required this.anonymous});

  final String question;
  final List<String> options;
  final bool anonymous;
}

/// Asks for a poll's question, its options (2 to 10) and whether it is
/// anonymous. Returns null if cancelled.
class CreatePollDialog extends StatefulWidget {
  const CreatePollDialog({super.key});

  static Future<NewPoll?> show(BuildContext context) =>
      showDialog<NewPoll>(context: context, builder: (_) => const CreatePollDialog());

  @override
  State<CreatePollDialog> createState() => _CreatePollDialogState();
}

class _CreatePollDialogState extends State<CreatePollDialog> {
  static const _minOptions = 2;
  static const _maxOptions = 10;

  final _question = TextEditingController();
  final List<TextEditingController> _options = [TextEditingController(), TextEditingController()];
  bool _anonymous = false;
  String? _error;

  @override
  void dispose() {
    _question.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final question = _question.text.trim();
    final options = _options.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    if (question.isEmpty) {
      setState(() => _error = 'Enter a question.');
      return;
    }
    if (options.length < _minOptions) {
      setState(() => _error = 'Enter at least $_minOptions options.');
      return;
    }
    if (options.map((o) => o.toLowerCase()).toSet().length != options.length) {
      setState(() => _error = 'Options must all be different.');
      return;
    }
    Navigator.pop(context, NewPoll(question: question, options: options, anonymous: _anonymous));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('create_poll_dialog'),
      title: const Text('Create poll'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('poll_question_field'),
                controller: _question,
                autofocus: true,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Question'),
              ),
              for (var i = 0; i < _options.length; i++)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: Key('poll_option_field_$i'),
                        controller: _options[i],
                        maxLength: 200,
                        decoration: InputDecoration(labelText: 'Option ${i + 1}', counterText: ''),
                      ),
                    ),
                    if (_options.length > _minOptions)
                      IconButton(
                        key: Key('poll_remove_option_$i'),
                        tooltip: 'Remove option',
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => setState(() => _options.removeAt(i).dispose()),
                      ),
                  ],
                ),
              if (_options.length < _maxOptions)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('poll_add_option_button'),
                    icon: const Icon(Icons.add),
                    label: const Text('Add option'),
                    onPressed: () => setState(() => _options.add(TextEditingController())),
                  ),
                ),
              SwitchListTile(
                key: const Key('poll_anonymous_switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Anonymous poll'),
                subtitle: const Text('Nobody can see who voted for what'),
                value: _anonymous,
                onChanged: (value) => setState(() => _anonymous = value),
              ),
              if (_error != null)
                Text(
                  _error!,
                  key: const Key('poll_form_error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(key: const Key('poll_create_submit'), onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}
