import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets.dart';
import '../keeper/keeper_shell.dart' show LicenseFooter;
import '../license/license_controller.dart';

class AdminShell extends ConsumerWidget {
  final String location;
  final Widget child;
  const AdminShell({super.key, required this.location, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider);
    return Theme(
      data: Theme.of(context).copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: Theme.of(context).filledButtonTheme.style?.copyWith(
                backgroundColor: WidgetStateProperty.resolveWith(
                  (s) => s.contains(WidgetState.disabled) ? const Color(0xFFB8C9C6) : const Color(0xFF0F4C5C),
                ),
              ),
        ),
      ),
      child: DesktopShell(
        palette: ShellPalette.admin,
        subtitle: 'لوحة السوبر أدمن',
        location: location,
        entries: const [
          NavEntry('الشركات', Icons.apartment_rounded, '/admin'),
          NavEntry('شركة جديدة', Icons.add_business_outlined, '/admin/new'),
        ],
        footer: LicenseFooter(palette: ShellPalette.admin, keyText: p.licenseKey),
        child: child,
      ),
    );
  }
}
