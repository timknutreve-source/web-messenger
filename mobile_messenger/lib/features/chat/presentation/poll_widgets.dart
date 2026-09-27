import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../domain/poll.dart';
import 'widgets/highlighted_text.dart';

/// A poll inside a message: what kind of poll it is, the question, each
/// option as a tappable row with an animated progress fill and its share of
/// the votes, and - for a public poll - who voted.
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
    final c = context.colors;
    final hasVoted = poll.myOptionId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: c.primarySoft,
            borderRadius: AppRadius.pillAll,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                poll.anonymous ? Icons.visibility_off_rounded : Icons.poll_rounded,
                size: 13,
                color: c.primary,
              ),
              const SizedBox(width: 5),
              Text(
                poll.anonymous ? 'Anonymous poll' : 'Public poll',
                key: const Key('poll_kind_label'),
                style: TextStyle(color: c.primary, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.2),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        HighlightedText(
          poll.question,
          query: highlight,
          style: theme.textTheme.titleSmall?.copyWith(fontSize: 15.5, height: 1.3),
        ),
        const SizedBox(height: 12),
        for (final option in poll.options)
          _PollOptionRow(
            key: Key('poll_option_${option.id}'),
            option: option,
            totalVotes: poll.totalVotes,
            selected: option.id == poll.myOptionId,
            showVoters: !poll.anonymous,
            onTap: () => option.id == poll.myOptionId ? onRetract() : onVote(option.id),
          ),
        const SizedBox(height: 2),
        Row(
          children: [
            Text(
              poll.totalVotes == 1 ? '1 vote' : '${poll.totalVotes} votes',
              key: const Key('poll_total_votes'),
              style: theme.textTheme.labelMedium?.copyWith(color: c.textSecondary),
            ),
            const Spacer(),
            if (hasVoted)
              TextButton.icon(
                key: const Key('poll_retract_button'),
                style: TextButton.styleFrom(
                  foregroundColor: c.error,
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                  textStyle: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                onPressed: onRetract,
                icon: const Icon(Icons.undo_rounded, size: 15),
                label: const Text('Retract vote'),
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
    final c = context.colors;
    final fraction = totalVotes == 0 ? 0.0 : option.voteCount / totalVotes;
    final percent = (fraction * 100).round();
    final voters = option.voters;
    final tone = selected ? c.accentGreen : c.textMuted;

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Semantics(
        button: true,
        selected: selected,
        label: '${option.text}, ${option.voteCount} ${option.voteCount == 1 ? 'vote' : 'votes'}'
            '${selected ? ', your vote' : ''}',
        excludeSemantics: true,
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: onTap,
              child: AnimatedContainer(
                duration: AppDurations.medium,
                curve: AppDurations.standard,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: selected ? c.accentGreen : c.border, width: selected ? 1.6 : 1),
                  color: selected ? c.successSoft : c.surfaceHover.withValues(alpha: 0.45),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md - 1),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(end: fraction),
                            duration: AppDurations.slow,
                            curve: AppDurations.standard,
                            builder: (context, value, _) => FractionallySizedBox(
                              widthFactor: value.clamp(0.0, 1.0),
                              heightFactor: 1,
                              child: ColoredBox(
                                color: (selected ? c.accentGreen : c.primary).withValues(alpha: selected ? 0.24 : 0.16),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                AnimatedSwitcher(
                                  duration: AppDurations.fast,
                                  child: Icon(
                                    selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                    key: Key(selected ? 'poll_option_selected_icon' : 'poll_option_unselected_icon'),
                                    size: 19,
                                    color: tone,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    option.text,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                                      color: c.textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  '${option.voteCount}',
                                  key: Key('poll_option_count_${option.id}'),
                                  style: theme.textTheme.labelLarge?.copyWith(color: c.textPrimary),
                                ),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 34,
                                  child: Text(
                                    '$percent%',
                                    textAlign: TextAlign.right,
                                    style: theme.textTheme.labelSmall?.copyWith(color: c.textSecondary),
                                  ),
                                ),
                              ],
                            ),
                            if (showVoters && voters != null && voters.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 5, left: 29),
                                child: Row(
                                  children: [
                                    Icon(Icons.people_alt_rounded, size: 13, color: c.textMuted),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                        voters.map((v) => v.username).join(', '),
                                        key: Key('poll_option_voters_${option.id}'),
                                        style: theme.textTheme.labelSmall?.copyWith(color: c.textSecondary),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
    final c = context.colors;
    return AlertDialog(
      key: const Key('create_poll_dialog'),
      icon: Icon(Icons.poll_rounded, color: c.primary),
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
                decoration: const InputDecoration(labelText: 'Question', counterText: ''),
              ),
              const SizedBox(height: 14),
              for (var i = 0; i < _options.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: Key('poll_option_field_$i'),
                          controller: _options[i],
                          maxLength: 200,
                          decoration: InputDecoration(
                            labelText: 'Option ${i + 1}',
                            counterText: '',
                            prefixIcon: Icon(Icons.radio_button_unchecked_rounded, size: 18, color: c.textMuted),
                          ),
                        ),
                      ),
                      if (_options.length > _minOptions)
                        IconButton(
                          key: Key('poll_remove_option_$i'),
                          tooltip: 'Remove option',
                          icon: Icon(Icons.remove_circle_outline_rounded, color: c.error),
                          onPressed: () => setState(() => _options.removeAt(i).dispose()),
                        ),
                    ],
                  ),
                ),
              if (_options.length < _maxOptions)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('poll_add_option_button'),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add option'),
                    onPressed: () => setState(() => _options.add(TextEditingController())),
                  ),
                ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: c.backgroundSecondary,
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(color: c.divider),
                ),
                child: SwitchListTile(
                  key: const Key('poll_anonymous_switch'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  secondary: Icon(Icons.visibility_off_rounded, color: c.textSecondary),
                  title: const Text('Anonymous poll'),
                  subtitle: const Text('Nobody can see who voted for what'),
                  value: _anonymous,
                  onChanged: (value) => setState(() => _anonymous = value),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    key: const Key('poll_form_error'),
                    style: TextStyle(color: c.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const Key('poll_create_submit'),
          style: FilledButton.styleFrom(minimumSize: const Size(96, 46)),
          onPressed: _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
