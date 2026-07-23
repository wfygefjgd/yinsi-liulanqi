import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yinsi_liulanqi/privacy_browser/privacy_browser_shell.dart';
import 'package:yinsi_liulanqi/privacy_browser/tab_manager.dart';

void main() {
  testWidgets('Privacy browser shell builds with bookmark home',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => TabManager(maxTabs: 3),
        child: const MaterialApp(home: PrivacyBrowserShell()),
      ),
    );
    await tester.pump();
    expect(find.text('搜索或输入网址'), findsOneWidget);
    expect(find.byTooltip('换新身份'), findsOneWidget);
    expect(find.text('Jiurelay'), findsOneWidget);
  });
}
