import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as host;
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/photo_sorter/organizer.dart';
import 'package:vaultexplorer/features/photo_sorter/photo_sorter_screen.dart';
import 'organizer_fakes.dart';

void main() {
  testWidgets(
    'sorter opens inside the real host widget and localization family',
    (tester) async {
      await tester.binding.setSurfaceSize(const host.Size(1536, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final protected = ProtectedMemory();
      final controller = OrganizerController(
        root: '/storage/fixtures',
        folder: '',
        photos: ['a.jpg', 'b.jpg'],
        repository: protected.repository(),
        bridge: FixtureBridge(),
      );
      await tester.pumpWidget(
        host.MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...host.GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: host.Builder(
            builder: (context) => host.Scaffold(
              body: host.TextButton(
                onPressed: () => host.Navigator.of(context).push(
                  host.MaterialPageRoute<void>(
                    builder: (_) => PhotoSorterScreen(
                      photos: controller.photos,
                      folderName: 'Files',
                      organizer: controller,
                      loadPreview: (_, _) async => null,
                    ),
                  ),
                ),
                child: const host.Text('Open sorter'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open sorter'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(host.TextField), findsOneWidget);
      expect(find.text('Choose your first destination folder'), findsOneWidget);
      expect(find.byType(host.GridView), findsOneWidget);
      expect(find.text('a.jpg'), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);
    },
  );
}
