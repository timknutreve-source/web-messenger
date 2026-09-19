import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../chat_search_providers.dart';

/// The in-chat search bar: query field, "n of m" position, previous/next match
/// and close. Searching only reads - it never touches the chat's own state.
class ChatSearchBar extends ConsumerStatefulWidget {
  const ChatSearchBar({super.key, required this.chatId});

  final String chatId;

  @override
  ConsumerState<ChatSearchBar> createState() => _ChatSearchBarState();
}

class _ChatSearchBarState extends ConsumerState<ChatSearchBar> {
  static const _debounce = Duration(milliseconds: 350);

  late final TextEditingController _field;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _field = TextEditingController(text: ref.read(chatSearchControllerProvider(widget.chatId)).query);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _field.dispose();
    super.dispose();
  }

  ChatSearchController get _controller => ref.read(chatSearchControllerProvider(widget.chatId).notifier);

  void _onChanged(String text) {
    _timer?.cancel();
    _timer = Timer(_debounce, () => _controller.search(text));
  }

  void _submit(String text) {
    _timer?.cancel();
    _controller.search(text);
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(chatSearchControllerProvider(widget.chatId));
    final theme = Theme.of(context);

    final String status;
    if (search.loading) {
      status = 'Searching...';
    } else if (search.error != null) {
      status = search.error!;
    } else if (search.noMatches) {
      status = 'No matches';
    } else if (search.hasResults) {
      status = '${search.currentIndex + 1} of ${search.results.length}${search.truncated ? '+' : ''}';
    } else {
      status = '';
    }

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Container(
        key: const Key('chat_search_bar'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('chat_search_field'),
                controller: _field,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search in this chat',
                  prefixIcon: Icon(Icons.search),
                  border: InputBorder.none,
                ),
                onChanged: _onChanged,
                onSubmitted: _submit,
              ),
            ),
            if (status.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  status,
                  key: Key(search.noMatches
                      ? 'chat_search_no_matches'
                      : search.error != null
                          ? 'chat_search_error'
                          : 'chat_search_count'),
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: search.error != null ? theme.colorScheme.error : null,
                  ),
                ),
              ),
            IconButton(
              key: const Key('chat_search_previous'),
              tooltip: 'Previous match',
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: search.hasResults ? _controller.previous : null,
            ),
            IconButton(
              key: const Key('chat_search_next'),
              tooltip: 'Next match',
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: search.hasResults ? _controller.next : null,
            ),
            IconButton(
              key: const Key('chat_search_close'),
              tooltip: 'Close search',
              icon: const Icon(Icons.close),
              onPressed: _controller.close,
            ),
          ],
        ),
      ),
    );
  }
}
