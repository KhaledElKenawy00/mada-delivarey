// الافتراضي: بيختار حسب المنصة (Windows → ديسكتوب، غير كده → موبايل)
import 'dart:io';

import 'app/app.dart';
import 'core/env.dart';

void main() =>
    bootstrap(Platform.isWindows || Platform.isMacOS || Platform.isLinux
        ? AppTarget.desktop
        : AppTarget.mobile);
