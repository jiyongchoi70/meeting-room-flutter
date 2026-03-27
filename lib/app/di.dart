import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/env/env.dart';

class AppDi {
  static Future<void> init() async {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
    );
  }
}
