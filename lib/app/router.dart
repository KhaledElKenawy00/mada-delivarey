import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/env.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../features/admin/admin_shell.dart';
import '../features/admin/companies_screen.dart';
import '../features/admin/company_licenses_screen.dart';
import '../features/admin/new_company_screen.dart';
import '../features/common/customers_screen.dart';
import '../features/common/live_map_screen.dart';
import '../features/common/profit_report_screen.dart';
import '../features/common/rep_report_screen.dart';
import '../features/keeper/keeper_dashboard_screen.dart';
import '../features/keeper/keeper_shell.dart';
import '../features/keeper/product_ledger_screen.dart';
import '../features/keeper/products_screen.dart';
import '../features/keeper/settlement_screen.dart';
import '../features/keeper/stock_issue_screen.dart';
import '../features/keeper/suppliers_screen.dart';
import '../features/license/activation_screen.dart';
import '../features/license/license_controller.dart';
import '../features/license/splash_screen.dart';
import '../features/manager/manager_overview_screen.dart';
import '../features/manager/manager_shell.dart';
import '../features/manager/reports_list_screen.dart';
import '../features/manager/warehouse_detail_screen.dart';
import '../features/rep/collection_screen.dart';
import '../features/rep/day_end_screen.dart';
import '../features/rep/rep_home_screen.dart';
import '../features/rep/sale_screen.dart';

String homeFor(Role r) => switch (r) {
      Role.superAdmin => '/admin',
      Role.manager => '/manager',
      Role.keeper => '/keeper',
      Role.rep => '/rep',
    };

Page<void> _page(Widget child) => NoTransitionPage(child: child);

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(licenseProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final lic = ref.read(licenseProvider);
      final target = ref.read(targetProvider);
      final loc = state.matchedLocation;
      switch (lic.status) {
        case LicenseStatus.checking:
          return loc == '/splash' ? null : '/splash';
        case LicenseStatus.needsActivation:
        case LicenseStatus.blocked:
          return loc == '/activate' ? null : '/activate';
        case LicenseStatus.active:
          final role = lic.profile!.role;
          final wrong = (target == AppTarget.mobile && role != Role.rep && role != Role.manager) || (target == AppTarget.desktop && role == Role.rep);
          if (wrong) return loc == '/wrong-device' ? null : '/wrong-device';
          final home = homeFor(role);
          if (loc == home || loc.startsWith('$home/')) return null;
          return home;
      }
    },
    routes: [
      GoRoute(path: '/splash', pageBuilder: (_, __) => _page(const SplashScreen())),
      GoRoute(path: '/activate', pageBuilder: (_, __) => _page(const ActivationScreen())),
      GoRoute(path: '/wrong-device', pageBuilder: (_, __) => _page(const WrongDeviceScreen())),

      // ── أمين المخزن (ديسكتوب)
      ShellRoute(
        builder: (context, state, child) => KeeperShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/keeper', pageBuilder: (_, __) => _page(const KeeperDashboardScreen()), routes: [
            GoRoute(path: 'issue', pageBuilder: (_, s) => _page(StockIssueScreen(initialRepId: s.uri.queryParameters['rep']))),
            GoRoute(path: 'settlements', pageBuilder: (_, __) => _page(const SettlementsScreen())),
            GoRoute(path: 'settlement/:id', pageBuilder: (_, s) => _page(SettlementScreen(sessionId: s.pathParameters['id']!))),
            GoRoute(path: 'products', pageBuilder: (_, __) => _page(const ProductsScreen())),
            GoRoute(path: 'products/:id/movements', pageBuilder: (_, s) => _page(ProductLedgerScreen(productId: s.pathParameters['id']!))),
            GoRoute(path: 'suppliers', pageBuilder: (_, __) => _page(const SuppliersScreen())),
            GoRoute(path: 'customers', pageBuilder: (_, __) => _page(const CustomersScreen())),
            GoRoute(path: 'map', pageBuilder: (_, __) => _page(const LiveMapScreen())),
            GoRoute(path: 'profit', pageBuilder: (_, __) => _page(const ProfitReportScreen())),
            GoRoute(path: 'reports', pageBuilder: (_, __) => _page(const ReportsListScreen(base: '/keeper'))),
            GoRoute(path: 'report/:rep', pageBuilder: (_, s) => _page(RepReportScreen(repId: s.pathParameters['rep']!))),
          ]),
        ],
      ),

      // ── مدير الشركة (ديسكتوب)
      ShellRoute(
        builder: (context, state, child) => ManagerShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/manager', pageBuilder: (_, __) => _page(const ManagerOverviewScreen()), routes: [
            GoRoute(path: 'warehouse/:id', pageBuilder: (_, s) => _page(WarehouseDetailScreen(warehouseId: s.pathParameters['id']!))),
            GoRoute(path: 'map', pageBuilder: (_, __) => _page(const LiveMapScreen(allWarehouses: true))),
            GoRoute(path: 'profit', pageBuilder: (_, __) => _page(const ProfitReportScreen())),
            GoRoute(path: 'reports', pageBuilder: (_, __) => _page(const ReportsListScreen(base: '/manager'))),
            GoRoute(path: 'report/:rep', pageBuilder: (_, s) => _page(RepReportScreen(repId: s.pathParameters['rep']!))),
            GoRoute(path: 'customers', pageBuilder: (_, __) => _page(const CustomersScreen())),
          ]),
        ],
      ),

      // ── السوبر أدمن (ديسكتوب)
      ShellRoute(
        builder: (context, state, child) => AdminShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/admin', pageBuilder: (_, __) => _page(const CompaniesScreen()), routes: [
            GoRoute(path: 'new', pageBuilder: (_, __) => _page(const NewCompanyScreen())),
            GoRoute(path: 'company/:id', pageBuilder: (_, s) => _page(CompanyLicensesScreen(companyId: s.pathParameters['id']!))),
          ]),
        ],
      ),

      // ── المندوب (موبايل)
      GoRoute(path: '/rep', pageBuilder: (_, __) => _page(const RepHomeScreen()), routes: [
        GoRoute(path: 'sale', builder: (_, __) => const SaleScreen()),
        GoRoute(path: 'collect', builder: (_, __) => const CollectionScreen()),
        GoRoute(path: 'day', builder: (_, __) => const DayEndScreen()),
        GoRoute(path: 'customers', builder: (_, __) => const CustomersScreen(mobile: true)),
      ]),
    ],
  );
});
