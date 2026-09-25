import 'dart:async';

import 'package:flutter/foundation.dart';

/// Transient, non-document state of canvas interactions: which overlay is
/// being dragged, whether it is over the trash, active snap guides and the
/// filter name shown after a swipe. Nothing here is exported.
class CanvasInteraction extends ChangeNotifier {
  String? _draggingId;
  bool _overTrash = false;
  bool _snapVertical = false;
  bool _snapHorizontal = false;
  String? _filterLabel;
  Timer? _labelTimer;

  /// Id of the overlay being dragged.
  String? get draggingId => _draggingId;

  /// Whether an overlay is being dragged.
  bool get dragging => _draggingId != null;

  /// Whether the dragged overlay is over the trash zone.
  bool get overTrash => _overTrash;

  /// Whether the overlay is snapped to the vertical centre line.
  bool get snapVertical => _snapVertical;

  /// Whether the overlay is snapped to the horizontal centre line.
  bool get snapHorizontal => _snapHorizontal;

  /// Filter name to show briefly, if any.
  String? get filterLabel => _filterLabel;

  /// An overlay drag started.
  void startDrag(String id) {
    _draggingId = id;
    _overTrash = false;
    _snapVertical = false;
    _snapHorizontal = false;
    notifyListeners();
  }

  /// Updates the drag feedback.
  void updateDrag({
    required bool overTrash,
    required bool snapVertical,
    required bool snapHorizontal,
  }) {
    if (overTrash == _overTrash &&
        snapVertical == _snapVertical &&
        snapHorizontal == _snapHorizontal) {
      return;
    }
    _overTrash = overTrash;
    _snapVertical = snapVertical;
    _snapHorizontal = snapHorizontal;
    notifyListeners();
  }

  /// The drag ended.
  void endDrag() {
    if (_draggingId == null) {
      return;
    }
    _draggingId = null;
    _overTrash = false;
    _snapVertical = false;
    _snapHorizontal = false;
    notifyListeners();
  }

  /// Shows [label] for [duration].
  void showFilterLabel(String label, Duration duration) {
    _labelTimer?.cancel();
    _filterLabel = label;
    notifyListeners();
    _labelTimer = Timer(duration, () {
      _filterLabel = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _labelTimer?.cancel();
    super.dispose();
  }
}
