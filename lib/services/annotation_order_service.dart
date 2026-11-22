/// Pure helpers for changing the visual order of annotation buttons.
/// These methods never change annotation records or their timestamps.
class AnnotationOrderService {
  const AnnotationOrderService._();

  /// Moves [draggedName] immediately before [targetName].
  static List<String> moveBefore({
    required List<String> current,
    required String draggedName,
    required String targetName,
  }) {
    final result = List<String>.from(current);
    final oldIndex = result.indexOf(draggedName);
    final targetIndex = result.indexOf(targetName);

    if (oldIndex < 0 || targetIndex < 0 || draggedName == targetName) {
      return result;
    }

    final moved = result.removeAt(oldIndex);
    final insertionIndex = oldIndex < targetIndex
        ? targetIndex - 1
        : targetIndex;
    result.insert(insertionIndex, moved);
    return result;
  }

  /// Moves [draggedName] to the last position.
  static List<String> moveToEnd({
    required List<String> current,
    required String draggedName,
  }) {
    final result = List<String>.from(current);
    final oldIndex = result.indexOf(draggedName);
    if (oldIndex < 0 || oldIndex == result.length - 1) return result;

    final moved = result.removeAt(oldIndex);
    result.add(moved);
    return result;
  }
}
