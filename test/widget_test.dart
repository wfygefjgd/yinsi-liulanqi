import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yinsi_liulanqi/privacy_browser/bookmarks.dart';
import 'package:yinsi_liulanqi/privacy_browser/privacy_browser_shell.dart';
import 'package:yinsi_liulanqi/privacy_browser/tab_manager.dart';

void main() {
  testWidgets('shell builds', (tester) async {
    final store = BookmarkStore();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: store),
          ChangeNotifierProvider(create: (_) => TabManager(maxTabs: 15)),
        ],
        child: const MaterialApp(home: PrivacyBrowserShell()),
      ),
    );
    await tester.pump();
    expect(find.text('搜索或输入网站'), findsOneWidget);
    expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);
    expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
  });
}
