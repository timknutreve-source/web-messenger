import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../../core/widgets/ambient_background.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_states.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_state.dart';
import '../../chat/chat_providers.dart';
import '../../chat/presentation/chat_info_panel.dart';
import '../../chat/presentation/chat_panel.dart';
import '../../chat/presentation/chats_screen.dart' show ChatListView;
import '../../contact/contact_providers.dart';
import '../../contact/domain/contact.dart';
import '../../contact/presentation/contacts_screen.dart';
import '../../group/group_providers.dart';
import '../../group/presentation/create_group_dialog.dart';
import '../../health/presentation/home_screen.dart' show pendingInvitationCountProvider, unreadMessageCountProvider;
import '../../profile/presentation/widgets/profile_avatar.dart';
import '../workspace_providers.dart';

/// The layout below this width is the phone layout (pages pushed on a stack).
const desktopBreakpoint = AppLayout.desktopBreakpoint;

const _navWidth = AppLayout.railWidth + AppLayout.listPaneWidth;

/// The wide-screen layout: a slim navigation rail, the chat/contact list, the
/// active chat in the middle (dominant, calm), and - when there is room - a
/// second chat side by side and/or a chat info pane at the right (members,
/// search results). Panes float as rounded surfaces over one ambient backdrop
/// so the whole thing reads as a single app.
class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({super.key});

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this)..addListener(_onTab);

  void _onTab() {
    if (!_tabs.indexIsChanging) setState(() {});
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTab);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceControllerProvider);
    final controller = ref.read(workspaceControllerProvider.notifier);

    return Scaffold(
      key: const Key('desktop_shell'),
      backgroundColor: context.colors.background,
      body: AmbientBackground(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final space = width - _navWidth;
            const minPanel = AppLayout.minChatPanelWidth;
            final canSplit = space >= minPanel * 2;
            final visibleIds = canSplit ? workspace.openChatIds : workspace.openChatIds.take(1).toList();
            final infoId = workspace.infoChatId;
            final infoFits = space >= minPanel * visibleIds.length.clamp(1, 2) + AppLayout.infoPaneWidth;
            final showInfoPane = infoId != null && visibleIds.contains(infoId) && infoFits;

            void onInfo(String chatId) {
              if (infoFits) {
                controller.toggleInfo(chatId);
              } else {
                showDialog<void>(
                  context: context,
                  builder: (_) => Dialog(
                    clipBehavior: Clip.antiAlias,
                    child: SizedBox(width: 420, height: 560, child: ChatInfoPanel(chatId: chatId)),
                  ),
                );
              }
            }

            return Row(
              children: [
                _NavRail(tabs: _tabs),
                SizedBox(
                  width: AppLayout.listPaneWidth,
                  child: _Pane(
                    margin: const EdgeInsets.fromLTRB(0, AppSpacing.md, AppSpacing.md, AppSpacing.md),
                    child: _LeftPane(tabs: _tabs, canSplit: canSplit),
                  ),
                ),
                Expanded(
                  child: visibleIds.isEmpty
                      ? const _Pane(
                          margin: EdgeInsets.fromLTRB(0, AppSpacing.md, AppSpacing.md, AppSpacing.md),
                          child: _NoChatSelected(),
                        )
                      : Row(
                          children: [
                            for (final id in visibleIds)
                              Expanded(
                                child: _Pane(
                                  margin: const EdgeInsets.fromLTRB(0, AppSpacing.md, AppSpacing.md, AppSpacing.md),
                                  child: ChatPanel(
                                    key: ValueKey('panel_$id'),
                                    chatId: id,
                                    header: ChatPanelHeader(
                                      chatId: id,
                                      infoActive: showInfoPane && infoId == id,
                                      onInfo: () => onInfo(id),
                                      onClose: () => controller.close(id),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
                if (showInfoPane)
                  SizedBox(
                    width: AppLayout.infoPaneWidth,
                    child: _Pane(
                      margin: const EdgeInsets.fromLTRB(0, AppSpacing.md, AppSpacing.md, AppSpacing.md),
                      child: ChatInfoPanel(chatId: infoId, onClose: controller.closeInfo),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A floating, rounded pane: the shell's basic building block.
class _Pane extends StatelessWidget {
  const _Pane({required this.child, this.margin = EdgeInsets.zero});

  final Widget child;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl - 2),
          border: Border.all(color: c.divider),
          boxShadow: AppShadows.card(c),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xl - 3),
          child: Material(color: Colors.transparent, child: child),
        ),
      ),
    );
  }
}

class _NoChatSelected extends StatelessWidget {
  const _NoChatSelected();

  @override
  Widget build(BuildContext context) {
    return const AppEmptyState(
      key: Key('desktop_empty_state'),
      icon: Icons.forum_rounded,
      title: 'Select a chat to start messaging',
      message: 'Pick a conversation from the list, or open two side by side to keep an eye on both.',
    );
  }
}

/// The slim left rail: brand, the four destinations (with live badges) and
/// the everyday utilities at the bottom.
class _NavRail extends ConsumerWidget {
  const _NavRail({required this.tabs});

  final TabController tabs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadMessageCountProvider);
    final invitations = ref.watch(pendingInvitationCountProvider);
    // Keep the invitation feed (and its live updates) running even while the
    // Invitations tab isn't the one on screen.
    ref.watch(pendingInvitationsControllerProvider);
    ref.watch(pendingGroupInvitationsControllerProvider);
    final mode = ref.watch(themeModeProvider);
    final dark = mode != ThemeMode.light;

    Widget item(int index, Key key, IconData icon, IconData activeIcon, String label, {int count = 0}) => _RailItem(
      key: key,
      icon: tabs.index == index ? activeIcon : icon,
      label: label,
      selected: tabs.index == index,
      count: count,
      onTap: () => tabs.animateTo(index),
    );

    return SizedBox(
      width: AppLayout.railWidth,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Column(
          children: [
            const BrandMark(size: 40),
            const SizedBox(height: AppSpacing.xl),
            Semantics(
              role: SemanticsRole.tabBar,
              container: true,
              child: Column(
                children: [
                  item(
                    0,
                    const Key('nav_chats_tab'),
                    Icons.chat_bubble_outline_rounded,
                    Icons.chat_bubble_rounded,
                    'Chats',
                    count: unread,
                  ),
                  item(
                    1,
                    const Key('nav_contacts_tab'),
                    Icons.people_outline_rounded,
                    Icons.people_rounded,
                    'Contacts',
                  ),
                  item(
                    2,
                    const Key('nav_invitations_tab'),
                    Icons.mail_outline_rounded,
                    Icons.mail_rounded,
                    'Invites',
                    count: invitations,
                  ),
                  item(3, const Key('nav_find_tab'), Icons.person_search_outlined, Icons.person_search_rounded, 'Find'),
                ],
              ),
            ),
            const Spacer(),
            IconButton(
              key: const Key('theme_toggle_button'),
              tooltip: dark ? 'Switch to light theme' : 'Switch to dark theme',
              icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
              onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
            ),
            IconButton(
              key: const Key('view_archived_chats_button'),
              tooltip: 'Archived chats',
              icon: const Icon(Icons.inventory_2_outlined),
              onPressed: () => context.push('/chats/archived'),
            ),
            IconButton(
              key: const Key('logout_button'),
              tooltip: 'Log out',
              icon: const Icon(Icons.logout_rounded),
              onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count = 0,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      role: SemanticsRole.tab,
      selected: selected,
      label: count > 0 ? '$label $count' : label,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: InkWell(
          borderRadius: AppRadius.mdAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
            child: SizedBox(
              width: 52,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: AppDurations.fast,
                        width: 48,
                        height: 34,
                        decoration: BoxDecoration(
                          color: selected ? c.primarySoft : Colors.transparent,
                          borderRadius: AppRadius.pillAll,
                        ),
                        child: Icon(icon, size: 22, color: selected ? c.primary : c.textSecondary),
                      ),
                      if (count > 0) Positioned(top: -4, right: -2, child: CountBadge(count: count, compact: true)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: selected ? c.primary : c.textMuted,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LeftPane extends ConsumerStatefulWidget {
  const _LeftPane({required this.tabs, required this.canSplit});

  final TabController tabs;
  final bool canSplit;

  @override
  ConsumerState<_LeftPane> createState() => _LeftPaneState();
}

class _LeftPaneState extends ConsumerState<_LeftPane> {
  final _search = TextEditingController();
  String _filter = '';

  static const _titles = ['Chats', 'Contacts', 'Invitations', 'Find people'];

  TabController get _tabs => widget.tabs;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_onTab);
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTab);
    _search.dispose();
    super.dispose();
  }

  void _onTab() {
    if (mounted) setState(() {});
  }

  Future<void> _newGroup() async {
    final group = await CreateGroupDialog.show(context);
    if (group == null || !mounted) return;
    ref.read(workspaceControllerProvider.notifier).open(group.id);
    _tabs.animateTo(0);
  }

  /// Opens the direct chat with a contact, if the chat list has it.
  void _openContact(Contact contact) {
    final chats = ref.read(chatsControllerProvider).value ?? const [];
    for (final chat in chats) {
      if (chat.otherUser?.id == contact.user.id) {
        ref.read(workspaceControllerProvider.notifier).open(chat.id);
        _tabs.animateTo(0);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider).value;
    final user = authState is AuthAuthenticated ? authState.user : null;
    final token = authState is AuthAuthenticated ? authState.token : null;
    final workspace = ref.watch(workspaceControllerProvider);
    final theme = Theme.of(context);
    final c = context.colors;

    return Column(
      key: const Key('left_pane'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.sm, AppSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  key: const Key('view_profile_button'),
                  borderRadius: AppRadius.pillAll,
                  onTap: () => context.push('/profile'),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: Row(
                      children: [
                        ProfileAvatar(
                          avatarFileName: user?.avatarFileName,
                          token: token,
                          radius: 19,
                          name: user?.username,
                          ring: true,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Flexible(
                          child: Text(
                            user?.username ?? '',
                            key: const Key('shell_username'),
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.chevron_right_rounded, size: 18, color: c.textMuted),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                key: const Key('new_group_button'),
                tooltip: 'New group',
                icon: const Icon(Icons.group_add_rounded),
                onPressed: _newGroup,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xs),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(_titles[_tabs.index], style: theme.textTheme.headlineSmall),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
                    child: TextField(
                      key: const Key('chat_list_search_field'),
                      controller: _search,
                      decoration: InputDecoration(
                        hintText: 'Search chats',
                        isDense: true,
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _filter.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _filter = '');
                                },
                              ),
                      ),
                      onChanged: (value) => setState(() => _filter = value),
                    ),
                  ),
                  Expanded(
                    child: ChatListView(
                      filter: _filter,
                      selectedChatIds: workspace.openChatIds.toSet(),
                      onOpen: (chat) => ref.read(workspaceControllerProvider.notifier).open(chat.id),
                      onOpenBeside: widget.canSplit
                          ? (chat) => ref.read(workspaceControllerProvider.notifier).openBeside(chat.id)
                          : null,
                    ),
                  ),
                ],
              ),
              ContactsTab(onOpenContact: _openContact),
              const PendingInvitationsTab(),
              const FindPeopleTab(),
            ],
          ),
        ),
      ],
    );
  }
}
