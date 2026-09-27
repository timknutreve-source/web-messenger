import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_badge.dart';
import '../../../../core/widgets/hover_reveal.dart';
import '../../domain/chat_summary.dart';
import 'chat_avatar.dart';

/// "14:05" today, "Yesterday", a weekday within the past week, else "12 Mar".
String formatChatTime(DateTime when, {DateTime? now}) {
  final at = when.toLocal();
  final today = now ?? DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);
  final startOfDay = DateTime(at.year, at.month, at.day);
  final days = startOfToday.difference(startOfDay).inDays;
  if (days <= 0) {
    return '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  }
  if (days == 1) return 'Yesterday';
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  if (days < 7) return weekdays[at.weekday - 1];
  final label = '${at.day} ${months[at.month - 1]}';
  return at.year == today.year ? label : '$label ${at.year}';
}

/// One row of a chat list: avatar, name, last-message preview, time, unread
/// badge. Selection is a gold wash *plus* a gold edge bar, so the open chat
/// reads at a glance; secondary [actions] appear on hover/focus (and are
/// always present when no mouse is connected).
class ChatListTile extends StatelessWidget {
  const ChatListTile({
    super.key,
    required this.tileKey,
    required this.chat,
    required this.token,
    this.onTap,
    this.selected = false,
    this.actions = const [],
    this.busy = false,
    this.trailing,
    this.unreadBadgeKey,
  });

  final Key tileKey;
  final ChatSummary chat;
  final String? token;
  final VoidCallback? onTap;
  final bool selected;

  /// Icon buttons shown on hover (or always on touch devices).
  final List<Widget> actions;

  /// Replaces the actions with a spinner while an action is in flight.
  final bool busy;

  /// Replaces the whole time/badge/actions column.
  final Widget? trailing;
  final Key? unreadBadgeKey;

  /// Badge and actions share the trailing slot. With a mouse the actions
  /// fade in over the badge on hover/focus; on touch both sit side by side so
  /// nothing depends on hovering. The actions are never removed from the tree,
  /// only faded, so keyboard and screen-reader users can always reach them.
  Widget _trailingSlot(bool revealed, bool mouse, bool unread) {
    final badge = unread ? CountBadge(key: unreadBadgeKey, count: chat.unreadCount, compact: true) : null;
    final actionRow = Row(mainAxisSize: MainAxisSize.min, children: actions);
    if (!mouse) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...actions,
          if (badge != null) ...[if (actions.isNotEmpty) const SizedBox(width: 4), badge],
        ],
      );
    }
    if (actions.isEmpty) return Align(alignment: Alignment.centerRight, child: badge);
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        if (badge != null) AnimatedOpacity(duration: AppDurations.fast, opacity: revealed ? 0 : 1, child: badge),
        AnimatedOpacity(
          duration: AppDurations.fast,
          opacity: revealed ? 1 : 0,
          alwaysIncludeSemantics: true,
          child: actionRow,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final unread = chat.unreadCount > 0;

    return HoverReveal(
      builder: (context, revealed) {
        final mouse = RendererBinding.instance.mouseTracker.mouseIsConnected;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 1),
          child: Stack(
            children: [
              ListTile(
                key: tileKey,
                selected: selected,
                onTap: onTap,
                contentPadding: const EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.sm),
                minVerticalPadding: 10,
                hoverColor: c.surfaceHover,
                leading: ChatAvatar(chat: chat, token: token, radius: 24),
                title: Text(
                  chat.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(
                    fontSize: 15,
                    fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _PreviewLine(chat: chat, unread: unread),
                ),
                trailing:
                    trailing ??
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          formatChatTime(chat.lastActivityAt),
                          style: text.labelSmall?.copyWith(
                            color: unread ? c.primary : c.textMuted,
                            fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 30,
                          child: busy
                              ? const Padding(
                                  padding: EdgeInsets.only(right: 6),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : _trailingSlot(revealed, mouse, unread),
                        ),
                      ],
                    ),
              ),
              // The selected chat's edge marker.
              Positioned(
                left: 0,
                top: 16,
                bottom: 16,
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: AppDurations.fast,
                    width: selected ? 3 : 0,
                    decoration: BoxDecoration(
                      color: c.primary,
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(3)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The last-message line. Attachments get an icon and a plain label rather
/// than an emoji; a group preview leads with the sender's name.
class _PreviewLine extends StatelessWidget {
  const _PreviewLine({required this.chat, required this.unread});

  final ChatSummary chat;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: unread ? c.textPrimary : c.textSecondary,
      fontWeight: unread ? FontWeight.w500 : FontWeight.w400,
    );
    final last = chat.lastMessage;
    final IconData? icon = last == null || last.deleted
        ? null
        : switch (last.attachmentType) {
            'IMAGE' => Icons.photo_rounded,
            'VIDEO' => Icons.videocam_rounded,
            'AUDIO' => Icons.mic_rounded,
            _ => null,
          };
    if (icon == null || last == null) {
      return Text(chat.previewText, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    }
    final label = switch (last.attachmentType) {
      'IMAGE' => 'Photo',
      'VIDEO' => 'Video',
      _ => 'Voice message',
    };
    final caption = last.content != null && last.content!.trim().isNotEmpty ? '  ${last.content}' : '';
    final sender = chat.isGroup && last.senderUsername != null ? '${last.senderUsername}: ' : '';
    return Row(
      children: [
        if (sender.isNotEmpty) Text(sender, style: style),
        Icon(icon, size: 15, color: style?.color),
        const SizedBox(width: 4),
        Expanded(
          child: Text('$label$caption', maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
        ),
      ],
    );
  }
}
