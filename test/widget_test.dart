// Basis-Smoke-Test: Die App startet ohne Fehler.
import 'package:flutter_test/flutter_test.dart';

import 'package:apex_mobile/main.dart';
import 'package:apex_mobile/services/credential_store.dart';
import 'package:apex_mobile/services/frappe_client.dart';

void main() {
  testWidgets('App startet ohne Fehler', (WidgetTester tester) async {
    final client = FrappeClient(CredentialStore());
    await tester.pumpWidget(ApexApp(client: client));
    expect(tester.takeException(), isNull);
  });
}
