import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';

/// Flutter Web에서 JS interop 예외 등이 [FlutterError.dumpErrorToConsole] 경로로
/// `LegacyJavaScriptObject is not a subtype of DiagnosticsNode` 를 유발할 수 있어,
/// 메시지·스택만 문자열로 출력한다.
void _installWebSafeErrorHandlers() {
  if (!kIsWeb) return;

  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('FlutterError: ${details.exceptionAsString()}');
    if (details.stack != null) {
      debugPrint(details.stack.toString());
    }
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('PlatformDispatcher.onError: $error');
    debugPrint(stack.toString());
    return true;
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installWebSafeErrorHandlers();
  await initializeDateFormatting('ko_KR');

  await dotenv.load(fileName: '.env');

  final supabaseUrl = (dotenv.env['SUPABASE_URL'] ?? '').trim();
  final supabaseAnonKey = (dotenv.env['SUPABASE_ANON_KEY'] ?? '').trim();

  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    throw Exception('SUPABASE_URL / SUPABASE_ANON_KEY is missing or empty in .env');
  }

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  runApp(const App());
}
