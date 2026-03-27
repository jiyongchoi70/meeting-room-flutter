import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
