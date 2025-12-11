import 'package:flutter/material.dart';
import '../components/ui/shell/home_shell.dart';
import '../components/ui/screen_capture_test_page.dart';
import '../components/ui/script_test_page.dart';

class AppRoutes {
  static const String root = '/';
  static const String feature = '/feature';
  static const String script = '/script';

  static Map<String, WidgetBuilder> buildRoutes() {
    return {
      root: (context) => const HomeShell(),
      feature: (context) => const ScreenCaptureTestPage(),
      script: (context) => const ScriptTestPage(),
    };
  }
}

