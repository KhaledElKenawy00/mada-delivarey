/// الإعدادات بتتبعت وقت التشغيل:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
/// من غيرهم التطبيق بيشتغل في وضع العرض (Demo) ببيانات تجريبية.
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static bool get demo => supabaseUrl.isEmpty || supabaseAnonKey.isEmpty;
}

enum AppTarget { desktop, mobile }
