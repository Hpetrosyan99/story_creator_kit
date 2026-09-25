import 'package:flutter/foundation.dart';

/// Linear undo/redo over immutable snapshots.
class History<T> extends ChangeNotifier {
  /// Starts with [initial] as the current value.
  History(T initial, {this.limit = 100}) : _current = initial;

  /// Maximum number of undo steps kept.
  final int limit;

  final List<T> _undo = [];
  final List<T> _redo = [];
  T _current;

  /// The current value.
  T get current => _current;

  /// Whether [undo] does something.
  bool get canUndo => _undo.isNotEmpty;

  /// Whether [redo] does something.
  bool get canRedo => _redo.isNotEmpty;

  /// Records [value] as a new step. Clears the redo stack. No-op when equal
  /// to the current value.
  void push(T value) {
    if (value == _current) {
      return;
    }
    _undo.add(_current);
    if (_undo.length > limit) {
      _undo.removeAt(0);
    }
    _redo.clear();
    _current = value;
    notifyListeners();
  }

  /// Replaces the current value without recording a step (e.g. during a
  /// drag; call [push] or [commitFrom] when the gesture ends).
  void replace(T value) {
    if (value == _current) {
      return;
    }
    _current = value;
    notifyListeners();
  }

  /// Records a step from [before] to the current value, for changes applied
  /// with [replace] during a gesture.
  void commitFrom(T before) {
    if (before == _current) {
      return;
    }
    _undo.add(before);
    if (_undo.length > limit) {
      _undo.removeAt(0);
    }
    _redo.clear();
    notifyListeners();
  }

  /// Steps back.
  void undo() {
    if (!canUndo) {
      return;
    }
    _redo.add(_current);
    _current = _undo.removeLast();
    notifyListeners();
  }

  /// Steps forward.
  void redo() {
    if (!canRedo) {
      return;
    }
    _undo.add(_current);
    _current = _redo.removeLast();
    notifyListeners();
  }
}
