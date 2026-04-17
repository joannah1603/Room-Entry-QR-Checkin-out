import 'package:flutter_test/flutter_test.dart';
import 'package:solution_hack_entryqr/main.dart';

void main() {
  testWidgets('AttendanceApp renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const AttendanceApp());
    await tester.pump();

    // The welcome text should be present
    expect(find.text('Welcome,'), findsOneWidget);
    expect(find.text('Employee EMP-2047'), findsOneWidget);
  });
}
