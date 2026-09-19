import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which chats are open in the wide layout: one, or two side by side, plus
/// the chat (if any) whose info pane is shown at the right.
class WorkspaceState {
  const WorkspaceState({this.openChatIds = const [], this.infoChatId});

  /// Up to two chat ids; the first is the primary (left/center) panel.
  final List<String> openChatIds;
  final String? infoChatId;

  String? get primaryChatId => openChatIds.isEmpty ? null : openChatIds.first;
}

class WorkspaceController extends Notifier<WorkspaceState> {
  static const maxPanels = 2;

  @override
  WorkspaceState build() => const WorkspaceState();

  /// Opens [chatId] in the primary panel (replacing what was there), unless
  /// it is already open in one of the panels.
  void open(String chatId) {
    final ids = state.openChatIds;
    if (ids.contains(chatId)) return;
    state = WorkspaceState(
      openChatIds: [chatId, ...ids.skip(1)],
      infoChatId: _infoAfter(state.infoChatId, chatId, ids),
    );
  }

  /// Opens [chatId] in the second panel next to the primary one.
  void openBeside(String chatId) {
    final ids = state.openChatIds;
    if (ids.isEmpty) {
      state = WorkspaceState(openChatIds: [chatId], infoChatId: state.infoChatId);
      return;
    }
    if (ids.first == chatId) return;
    state = WorkspaceState(openChatIds: [ids.first, chatId], infoChatId: state.infoChatId);
  }

  void close(String chatId) {
    final remaining = state.openChatIds.where((id) => id != chatId).toList();
    state = WorkspaceState(
      openChatIds: remaining,
      infoChatId: state.infoChatId == chatId ? null : state.infoChatId,
    );
  }

  void toggleInfo(String chatId) {
    state = WorkspaceState(
      openChatIds: state.openChatIds,
      infoChatId: state.infoChatId == chatId ? null : chatId,
    );
  }

  void closeInfo() => state = WorkspaceState(openChatIds: state.openChatIds);

  // The info pane follows the chat it describes: if that chat is being
  // replaced in the primary panel, the pane closes with it.
  String? _infoAfter(String? info, String opened, List<String> previous) {
    if (info == null || previous.isEmpty) return info;
    return previous.first == info && opened != info && !previous.skip(1).contains(info) ? null : info;
  }
}

final workspaceControllerProvider = NotifierProvider<WorkspaceController, WorkspaceState>(WorkspaceController.new);
