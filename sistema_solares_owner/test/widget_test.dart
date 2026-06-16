import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares_owner/main.dart';

void main() {
  testWidgets('owner app renders title', (tester) async {
    await tester.pumpWidget(const OwnerApp());
    expect(find.text('Sistema Solares Owner'), findsOneWidget);
  });
}
