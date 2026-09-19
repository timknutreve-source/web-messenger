import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/features/shell/workspace_providers.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  WorkspaceController controller() => container.read(workspaceControllerProvider.notifier);
  WorkspaceState state() => container.read(workspaceControllerProvider);

  test('starts with nothing open', () {
    expect(state().openChatIds, isEmpty);
    expect(state().primaryChatId, isNull);
    expect(state().infoChatId, isNull);
  });

  test('opening a chat makes it the primary panel and replaces the previous primary', () {
    controller().open('a');
    expect(state().openChatIds, ['a']);

    controller().open('b');
    expect(state().openChatIds, ['b']);
  });

  test('opening a chat beside the primary adds a second panel, never more than two', () {
    controller().open('a');
    controller().openBeside('b');
    expect(state().openChatIds, ['a', 'b']);

    controller().openBeside('c');
    expect(state().openChatIds, ['a', 'c'], reason: 'the second panel is replaced, not a third added');
  });

  test('opening beside with nothing open just opens it', () {
    controller().openBeside('a');
    expect(state().openChatIds, ['a']);
  });

  test('opening the chat that is already the primary changes nothing', () {
    controller().open('a');
    controller().openBeside('b');

    controller().openBeside('a');
    controller().open('a');
    controller().open('b');

    expect(state().openChatIds, ['a', 'b']);
  });

  test('opening a chat while two are open replaces only the primary', () {
    controller().open('a');
    controller().openBeside('b');

    controller().open('c');

    expect(state().openChatIds, ['c', 'b']);
  });

  test('closing the primary promotes the second panel', () {
    controller().open('a');
    controller().openBeside('b');

    controller().close('a');

    expect(state().openChatIds, ['b']);
    expect(state().primaryChatId, 'b');
  });

  test('closing the last chat leaves an empty workspace', () {
    controller().open('a');
    controller().close('a');
    expect(state().openChatIds, isEmpty);
  });

  test('the info pane toggles for a chat and closes with it', () {
    controller().open('a');
    controller().toggleInfo('a');
    expect(state().infoChatId, 'a');

    controller().toggleInfo('a');
    expect(state().infoChatId, isNull);

    controller().toggleInfo('a');
    controller().close('a');
    expect(state().infoChatId, isNull);
  });

  test('the info pane closes when its chat is replaced in the primary panel', () {
    controller().open('a');
    controller().toggleInfo('a');

    controller().open('b');

    expect(state().infoChatId, isNull);
    expect(state().openChatIds, ['b']);
  });

  test('closeInfo closes the pane and keeps the chats', () {
    controller().open('a');
    controller().openBeside('b');
    controller().toggleInfo('b');

    controller().closeInfo();

    expect(state().infoChatId, isNull);
    expect(state().openChatIds, ['a', 'b']);
  });
}
