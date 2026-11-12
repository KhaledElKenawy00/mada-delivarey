# تعليمات للـ AI Agent — تشغيل مدار وربطه بـ Supabase

أنت بتساعد صاحب المشروع (خالد) يشغّل مشروع Flutter اسمه **مدار** ويربطه بـ Supabase.
اقرأ `README.md` الأول للصورة العامة. بعدها نفّذ الخطوات دي **بالترتيب**.
علّم على كل خطوة لما تخلص، ولو أي خطوة فشلت صلّحها قبل ما تكمل.

## قواعد مهمة
- **ماتكتبش أي مفاتيح أو باسوردات في ملفات بتترفع على git.** المفاتيح مكانها `env.json` بس، وهو موجود في `.gitignore`.
- **ماتعدّلش منطق البيزنس في `supabase/schema.sql` أو `lib/data/*`.** الاستثناء الوحيد إنك تصلّح خطأ compile أو SQL حقيقي، وساعتها اشرح التعديل.
- **ماتستخدمش `service_role key` في التطبيق أبداً.** التطبيق بياخد `anon` أو `publishable key` بس.
- **أي حاجة محتاجة دخول على حساب** (إنشاء مشروع Supabase، `supabase login`، باسورد الداتابيز، إنشاء أول مستخدم): اطلبها من خالد وماتخمّنهاش.
- **اكتب ردودك لخالد بالعامية المصرية.**

---

## الخطوة 0 — التأكد من الأدوات
```bash
flutter --version          # لازم 3.27 أو أحدث
flutter doctor             # Windows: لازم "Visual Studio - develop Windows apps" يبقى ✓
node --version             # لـ Supabase CLI
npx supabase --version     # أو: npm i -g supabase
```
لو حاجة ناقصة، قول لخالد يسطّبها إزاي ووقّف لحد ما يسطّبها.

## الخطوة 1 — توليد فولدرات المنصات
```bash
flutter create . --platforms=android,windows --org com.madar --project-name madar
```
الأمر ده مش هيلمس `lib/` ولا `pubspec.yaml`. لو `flutter create` ولّد `test/widget_test.dart` بيشاور على `MyApp`، احذفه.

## الخطوة 2 — إعداد Android
في `android/app/src/main/AndroidManifest.xml` ضيف اللي في `docs/android_manifest.xml`:
- صلاحيات `uses-permission` فوق `<application>`.
- `<service ... GeolocatorLocationService ...>` جوه `<application>`.

كمان:
- خلّي `android:label="مدار"`.
- في `android/app/build.gradle` (أو `.kts`) اتأكد إن `minSdk` = 23 أو أكتر. `flutter_secure_storage` و `sunmi_printer_plus` محتاجينه.

## الخطوة 3 — الباكدجات والتحليل
```bash
flutter pub get
flutter analyze
```
- صلّح **كل الـ errors**. الـ warnings والـ infos مش لازم.
- **أكتر حاجتين متوقع يحتاجوا تعديل بسبب اختلاف إصدارات المكتبات:**
  - `lib/features/print/receipt.dart` في `ReceiptPrinter.printPng`. دي الدالة الوحيدة اللي بتتعامل مع `sunmi_printer_plus`. راجع API الإصدار اللي اتسطّب (`printImage` و `lineWrap` و `cutPaper`) وعدّلها عليه.
  - `lib/features/import/excel_import.dart`. راجع أسماء `TextCellValue` و `DoubleCellValue` و `getDefaultSheet` في باكدج `excel` اللي اتسطّب.
- لو `pub get` فشل بسبب تعارض إصدارات: جرّب `flutter pub upgrade --major-versions` وبعدها صلّح أي API اتغير.

## الخطوة 4 — جرّب وضع العرض (Demo) قبل Supabase
```bash
flutter run -d windows -t lib/main_desktop.dart
```
- التطبيق لازم يفتح على شاشة التفعيل. جرّب مفتاح `MDR-DEMO-KEEP-0001`.
- لو فيه أخطاء runtime صلّحها.
- (اختياري، لو فيه موبايل متوصل) `flutter run -t lib/main_mobile.dart` بالمفتاح `MDR-DEMO-REP1-0001`.

## الخطوة 5 — ربط Supabase
اطلب من خالد الحاجات دي، **وماتكملش من غيرها**:
1. يعمل مشروع على https://supabase.com/dashboard (لو مش عامل).
2. **Project Ref**: موجود في Settings › General.
3. **Database password**: الباسورد اللي حطه وقت إنشاء المشروع.
4. **Project URL** و **anon / publishable key**: موجودين في Settings › API.

بعدها نفّذ:
```bash
npx supabase login                                  # بيفتح المتصفح — خالد يوافق
npx supabase link --project-ref <PROJECT_REF>       # هيطلب باسورد الداتابيز
npx supabase db push                                # بيرفع supabase/migrations/*.sql
npx supabase functions deploy activate-license --no-verify-jwt
npx supabase functions deploy admin --no-verify-jwt
```
- لو `db push` فشل في SQL، صلّح الخطأ في **الملفين**: `supabase/schema.sql` و `supabase/migrations/20261105000000_madar_init.sql`. لازم يفضلوا متطابقين.
- **اتأكد من النتيجة:**
  - `npx supabase functions list` لازم يطلّع الاتنين.
  - من SQL Editor أو `npx supabase db execute` لازم الجداول تكون موجودة: `companies` و `licenses` و `products`... إلخ.

## الخطوة 6 — ملف env.json
اعمل `env.json` في جذر المشروع، على شكل `env.example.json`، بالقيم الحقيقية اللي خالد اداها:
```json
{ "SUPABASE_URL": "https://<ref>.supabase.co", "SUPABASE_ANON_KEY": "<anon-or-publishable-key>" }
```

## الخطوة 7 — أول سوبر أدمن
1. خالد يعمل مستخدم من Dashboard › Authentication › Users › **Add user** (إيميل + باسورد + Auto Confirm).
2. خد منه الـ **User UID**.
3. شغّل في SQL Editor (أو قوله يشغّله):
   ```sql
   select bootstrap_super_admin('<USER_UID>', 'خالد');
   ```
4. الناتج مفتاح بالشكل `MDR-XXXX-XXXX-XXXX`. **اديه لخالد.**

## الخطوة 8 — التشغيل الحقيقي
```bash
flutter run -d windows -t lib/main_desktop.dart --dart-define-from-file=env.json
```
أو من VS Code بإعداد **«مدار ديسكتوب — Supabase»** (F5).

1. خالد يكتب مفتاح السوبر أدمن، والمفروض يفتح على **لوحة الشركات**.
2. **اختبار نهاية لنهاية** (ساعده يعمله):
   1. **شركة جديدة**: مخزن واحد ومندوبين → تظهر المفاتيح.
   2. التفعيل بمفتاح **أمين المخزن** على نفس الجهاز يتطلب امسح التفعيل الحالي الأول:
      ```dart
      const FlutterSecureStorage().deleteAll()
      ```
      أو امسح بيانات التطبيق. الأسهل: شغّل نسخة الديسكتوب على جهاز تاني لأمين المخزن.
   3. أمين المخزن: **الأصناف › استيراد من Excel** (نموذج) → استلام بضاعة → **صرف بضاعة** لمندوب.
   4. على الموبايل (بمفتاح المندوب): `--dart-define-from-file=env.json -t lib/main_mobile.dart` → **فاتورة بيع** → **إنهاء اليوم**.
   5. أمين المخزن: **تسوية العهد** → اعتماد.
   6. السوبر أدمن: **فك ربط جهاز** → يتأكد إن الجهاز القديم بيتقفل في خلال 10 دقايق أو عند إعادة الفتح.

## لو حصلت مشاكل
| العَرَض | السبب المحتمل |
|---|---|
| `INVALID_KEY` | المفتاح غلط، أو الـ Edge Function مش متنشرة |
| `ALREADY_BOUND` | المفتاح متفعل على جهاز تاني → فك الربط من السوبر أدمن |
| `FunctionException 401` | الفانكشن اتنشرت من غير `--no-verify-jwt` |
| `PGRST202 function not found` | الـ migration ماترفعتش → `npx supabase db push` |
| التطبيق بيفتح Demo بالرغم من Supabase | `env.json` مش متبعت → اتأكد من `--dart-define-from-file=env.json` |
| الطباعة مش شغالة | الجهاز مش Sunmi، أو API `sunmi_printer_plus` محتاج تعديل في `ReceiptPrinter.printPng` |

لما تخلص، اكتب لخالد ملخص قصير بالعامية المصرية فيه:
- اتعمل إيه.
- إيه اللي اتعدّل في الكود ولماذا.
- إيه اللي لسه محتاجه منه.
