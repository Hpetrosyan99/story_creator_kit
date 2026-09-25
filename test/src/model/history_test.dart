import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/src/model/history.dart';

void main() {
  late History<int> history;
  late int notifications;

  setUp(() {
    history = History<int>(0);
    notifications = 0;
    history.addListener(() => notifications++);
  });

  tearDown(() => history.dispose());

  test('starts at the initial value with nothing to undo or redo', () {
    expect(history.current, 0);
    expect(history.canUndo, isFalse);
    expect(history.canRedo, isFalse);
  });

  group('push', () {
    test('records a step and notifies', () {
      history.push(1);

      expect(history.current, 1);
      expect(history.canUndo, isTrue);
      expect(notifications, 1);
    });

    test('is a no-op for a value equal to the current one', () {
      history.push(0);

      expect(history.canUndo, isFalse);
      expect(notifications, 0);
    });

    test('clears the redo stack', () {
      history
        ..push(1)
        ..push(2)
        ..undo();
      expect(history.canRedo, isTrue);

      history.push(3);

      expect(history.canRedo, isFalse);
      expect(history.current, 3);
      history.undo();
      expect(history.current, 1);
    });
  });

  group('undo / redo', () {
    test('walk back and forth through the steps', () {
      history
        ..push(1)
        ..push(2)
        ..push(3)
        ..undo()
        ..undo();

      expect(history.current, 1);
      expect(history.canRedo, isTrue);

      history.redo();
      expect(history.current, 2);
      history.redo();
      expect(history.current, 3);
      expect(history.canRedo, isFalse);
    });

    test('undo back to the initial value, then nothing more', () {
      history
        ..push(1)
        ..undo();

      expect(history.current, 0);
      expect(history.canUndo, isFalse);

      final before = notifications;
      history.undo();
      expect(history.current, 0);
      expect(notifications, before, reason: 'no-op undo must not notify');
    });

    test('redo without a redo step is a no-op', () {
      history
        ..push(1)
        ..redo();

      expect(history.current, 1);
      expect(notifications, 1);
    });
  });

  group('replace + commitFrom (gestures)', () {
    test('replace changes the value without recording a step', () {
      history.replace(5);

      expect(history.current, 5);
      expect(history.canUndo, isFalse);
      expect(notifications, 1);
    });

    test('replace with an equal value does not notify', () {
      history.replace(0);

      expect(notifications, 0);
    });

    test('commitFrom records one step for the whole gesture', () {
      history.push(1);
      final before = history.current;
      history
        ..replace(2)
        ..replace(3)
        ..replace(4)
        ..commitFrom(before);

      expect(history.current, 4);
      history.undo();
      expect(history.current, 1, reason: 'the intermediate values are skipped');
      history.redo();
      expect(history.current, 4);
    });

    test('commitFrom clears the redo stack', () {
      history
        ..push(1)
        ..push(2)
        ..undo();
      final before = history.current;
      history
        ..replace(7)
        ..commitFrom(before);

      expect(history.canRedo, isFalse);
    });

    test('commitFrom is a no-op when nothing changed', () {
      history
        ..push(1)
        ..replace(2)
        ..replace(1)
        ..commitFrom(1)
        ..undo();
      expect(history.current, 0, reason: 'no extra step was recorded');
    });
  });

  group('limit', () {
    test('keeps at most limit undo steps, dropping the oldest', () {
      final limited = History<int>(0, limit: 3);
      for (var i = 1; i <= 5; i++) {
        limited.push(i);
      }

      var undos = 0;
      while (limited.canUndo) {
        limited.undo();
        undos++;
      }

      expect(undos, 3);
      expect(limited.current, 2);
      limited.dispose();
    });

    test('commitFrom also respects the limit', () {
      final limited = History<int>(0, limit: 2);
      for (var i = 1; i <= 4; i++) {
        final before = limited.current;
        limited
          ..replace(i)
          ..commitFrom(before);
      }

      var undos = 0;
      while (limited.canUndo) {
        limited.undo();
        undos++;
      }

      expect(undos, 2);
      expect(limited.current, 2);
      limited.dispose();
    });
  });
}
