import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_annotator/services/annotation_order_service.dart';

void main() {
  group('AnnotationOrderService', () {
    test('moves a button before another button', () {
      final result = AnnotationOrderService.moveBefore(
        current: ['BUMP', 'POTHOLE', 'OTHER', 'RAILWAY'],
        draggedName: 'RAILWAY',
        targetName: 'POTHOLE',
      );

      expect(result, ['BUMP', 'RAILWAY', 'POTHOLE', 'OTHER']);
    });

    test('moves a first button before a later target', () {
      final result = AnnotationOrderService.moveBefore(
        current: ['BUMP', 'POTHOLE', 'OTHER'],
        draggedName: 'BUMP',
        targetName: 'OTHER',
      );

      expect(result, ['POTHOLE', 'BUMP', 'OTHER']);
    });

    test('moves a button to the end', () {
      final result = AnnotationOrderService.moveToEnd(
        current: ['BUMP', 'POTHOLE', 'OTHER'],
        draggedName: 'BUMP',
      );

      expect(result, ['POTHOLE', 'OTHER', 'BUMP']);
    });

    test('does not change the list when source or target is missing', () {
      final current = ['BUMP', 'POTHOLE'];
      final result = AnnotationOrderService.moveBefore(
        current: current,
        draggedName: 'UNKNOWN',
        targetName: 'POTHOLE',
      );

      expect(result, current);
      expect(identical(result, current), isFalse);
    });

    test('does not change the list when moving a button onto itself', () {
      final result = AnnotationOrderService.moveBefore(
        current: ['BUMP', 'POTHOLE'],
        draggedName: 'BUMP',
        targetName: 'BUMP',
      );

      expect(result, ['BUMP', 'POTHOLE']);
    });
  });
}
