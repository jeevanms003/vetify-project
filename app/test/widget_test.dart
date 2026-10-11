import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';
import 'package:app/services/dataset_repository.dart';
import 'package:app/services/audit_logger.dart';
import 'package:app/services/search_service.dart';

void main() {
  testWidgets('VetifiApp loads and displays tabs', (WidgetTester tester) async {
    final repo = DatasetRepository();
    final auditLogger = AuditLogger();
    final search = SearchService();

    await tester.pumpWidget(VetifiApp(
      repository: repo,
      auditLogger: auditLogger,
      searchService: search,
    ));

    expect(find.text('Clinical Dose Calculator'), findsOneWidget);
    expect(find.text('Dose'), findsOneWidget);
    expect(find.text('CRI Infusion'), findsOneWidget);
  });
}
