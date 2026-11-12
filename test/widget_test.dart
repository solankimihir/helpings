import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/app.dart';

void main() {
  testWidgets('app boots', (tester) async {
    await tester.pumpWidget(const HelpingsApp());
    expect(find.text('Helpings'), findsOneWidget);
  });
}
