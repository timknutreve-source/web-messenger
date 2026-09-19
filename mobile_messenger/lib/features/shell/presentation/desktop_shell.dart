import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
const desktopBreakpoint = 900.0;

/// The width a chat panel needs to be comfortable, which decides how many
/// panels (and whether the info pane) fit next to the navigation column.
const _minPanelWidth = 380.0;
const _leftPaneWidth = 340.0;
const _infoPaneWidth = 340.0;

/// The wide-screen layout: navigation on the left (profile, chats, contacts,
/// invitations, people search), the active chat in the middle, and - when
/// there is room - a second chat side by side and/or a chat info pane at the
/// right (members, search results).
class DesktopShell extends ConsumerWidget {
  const DesktopShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(workspaceControllerProvider);
    final controller = ref.read(workspaceControllerProvider.notifier);

    return Scaffold(
      key: const Key('desktop_shell'),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final space = width - _leftPaneWidth;
          final canSplit = space >= _minPanelWidth * 2;
          final visibleIds = canSplit ? workspace.openChatIds : workspace.openChatIds.take(1).toList();
          final infoId = workspace.infoChatId;
          final infoFits = space >= _minPanelWidth * visibleIds.length.clamp(1, 2) + _infoPaneWidth;
          final showInfoPane = infoId != null && visibleIds.contains(infoId) && infoFits;

          void onInfo(String chatId) {
            if (infoFits) {
              controller.toggleInfo(chatId);
            } else {
              showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  child: SizedBox(width: 420, height: 560, child: ChatInfoPanel(chatId: chatId)),
                ),
              );
            }
          }

          return Row(
            children: [
              SizedBox(
                width: _leftPaneWidth,
                child: _LeftPane(canSplit: canSplit),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: visibleIds.isEmpty
                    ? const _NoChatSelected()
                    : Row(
                        children: [
                          for (var i = 0; i < visibleIds.length; i++) ...[
                            if (i > 0) const VerticalDivider(width: 1),
                            Expanded(
                              child: ChatPanel(
                                key: ValueKey('panel_${visibleIds[i]}'),
                                chatId: visibleIds[i],
                                header: ChatPanelHeader(
                                  chatId: visibleIds[i],
                                  infoActive: showInfoPane && infoId == visibleIds[i],
                                  onInfo: () => onInfo(visibleIds[i]),
                                  onClose: () => controller.close(visibleIds[i]),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
              if (showInfoPane) ...[
                const VerticalDivider(width: 1),
                SizedBox(
                  width: _infoPaneWidth,
                  child: ChatInfoPanel(chatId: infoId, onClose: controller.closeInfo),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _NoChatSelected extends StatelessWidget {
  const _NoChatSelected();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const Key('desktop_empty_state'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined, size: 56, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('Select a chat to start messaging', style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _LeftPane extends ConsumerStatefulWidget {
  const _LeftPane({required this.canSplit});

  final bool canSplit;

  @override
  ConsumerState<_LeftPane> createState() => _LeftPaneState();
}

class _LeftPaneState extends ConsumerState<_LeftPane> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  final _search = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
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
    final unread = ref.watch(unreadMessageCountProvider);
    final invitations = ref.watch(pendingInvitationCountProvider);
    // Keep the invitation feed (and its live updates) running even while the
    // Invitations tab isn't the one on screen.
    ref.watch(pendingInvitationsControllerProvider);
    ref.watch(pendingGroupInvitationsControllerProvider);
    final theme = Theme.of(context);

    return Material(
      key: const Key('left_pane'),
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                InkWell(
                  key: const Key('view_profile_button'),
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => context.push('/profile'),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ProfileAvatar(avatarFileName: user?.avatarFileName, token: token, radius: 18),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 130),
                          child: Text(
                            user?.username ?? '',
                            key: const Key('shell_username'),
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  key: const Key('new_group_button'),
                  tooltip: 'New group',
                  icon: const Icon(Icons.group_add_outlined),
                  onPressed: _newGroup,
                ),
                IconButton(
                  key: const Key('view_archived_chats_button'),
                  tooltip: 'Archived chats',
                  icon: const Icon(Icons.archive_outlined),
                  onPressed: () => context.push('/chats/archived'),
                ),
                IconButton(
                  key: const Key('logout_button'),
                  tooltip: 'Log out',
                  icon: const Icon(Icons.logout),
                  onPressed: () => ref.read(authControllerProvider.notifier).logout(),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabs,
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            labelStyle: theme.textTheme.labelLarge,
            tabs: [
              Tab(
                key: const Key('nav_chats_tab'),
                child: _TabLabel('Chats', count: unread),
              ),
              const Tab(key: Key('nav_contacts_tab'), text: 'Contacts'),
              Tab(
                key: const Key('nav_invitations_tab'),
                child: _TabLabel('Invites', count: invitations),
              ),
              const Tab(key: Key('nav_find_tab'), text: 'Find'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      child: TextField(
                        key: const Key('chat_list_search_field'),
                        controller: _search,
                        decoration: InputDecoration(
                          hintText: 'Search chats',
                          isDense: true,
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                          suffixIcon: _filter.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  icon: const Icon(Icons.clear),
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
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel(this.label, {required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        if (count > 0) ...[
          const SizedBox(width: 4),
          Badge(label: Text('$count')),
        ],
      ],
    );
  }
}
