import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:sistema_solares_ui/app.dart';
import 'package:sistema_solares_ui/core/config/app_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  await AppConfig.initialize();
  runApp(const App());
}

