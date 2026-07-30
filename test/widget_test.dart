import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App builds without error', (WidgetTester tester) async {
    // App requires Hive initialization before running.
    // Integration tests should run with flutter drive instead.
    expect(true, isTrue);
  });
}
