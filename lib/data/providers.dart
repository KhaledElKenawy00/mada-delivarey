import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/device_identity.dart';
import '../core/env.dart';
import 'demo_repository.dart';
import 'models.dart';
import 'repository.dart';
import 'supabase_repository.dart';

/// بيتحدد في main_desktop.dart / main_mobile.dart
final targetProvider = Provider<AppTarget>((ref) => throw UnimplementedError('override targetProvider'));

final repositoryProvider = Provider<MadarRepository>((ref) => Env.demo ? DemoRepository() : SupabaseRepository());

final deviceIdentityProvider = FutureProvider<DeviceIdentity>((ref) => DeviceIdentity.read());

// ── بيانات الشاشات (ref.invalidate لما تحب تحدّث)
final warehouseLiveProvider = FutureProvider.autoDispose.family<WarehouseLive, String?>(
  (ref, id) => ref.watch(repositoryProvider).warehouseLive(id),
);

final sessionDataProvider = FutureProvider.autoDispose.family<SessionData, String>(
  (ref, id) => ref.watch(repositoryProvider).sessionData(id),
);

final customersProvider = FutureProvider.autoDispose<List<Customer>>(
  (ref) => ref.watch(repositoryProvider).customers(),
);

final suppliersProvider = FutureProvider.autoDispose<List<Supplier>>(
  (ref) => ref.watch(repositoryProvider).suppliers(),
);

final supplierPaymentsProvider = FutureProvider.autoDispose.family<List<SupplierPayment>, String>(
  (ref, supplierId) => ref.watch(repositoryProvider).supplierPayments(supplierId),
);

final myCustodyProvider = FutureProvider.autoDispose<SessionData?>(
  (ref) => ref.watch(repositoryProvider).myCustody(),
);

final companyOverviewProvider = FutureProvider.autoDispose<CompanyOverview>(
  (ref) => ref.watch(repositoryProvider).companyOverview(),
);

typedef ReportArgs = ({String repId, DateTime from, DateTime to});

final repReportProvider = FutureProvider.autoDispose.family<RepReport, ReportArgs>(
  (ref, a) => ref.watch(repositoryProvider).repReport(a.repId, a.from, a.to),
);

typedef ProfitArgs = ({DateTime from, DateTime to, String? warehouseId});

final profitReportProvider = FutureProvider.autoDispose.family<ProfitReport, ProfitArgs>(
  (ref, a) => ref.watch(repositoryProvider).profitReport(a.from, a.to, warehouseId: a.warehouseId),
);

typedef ProductLedgerArgs = ({String productId, DateTime from, DateTime to});

final productLedgerProvider = FutureProvider.autoDispose.family<ProductLedger, ProductLedgerArgs>(
  (ref, a) => ref.watch(repositoryProvider).productLedger(a.productId, a.from, a.to),
);

final companiesProvider = FutureProvider.autoDispose<List<CompanyRow>>(
  (ref) => ref.watch(repositoryProvider).companies(),
);

final companyLicensesProvider = FutureProvider.autoDispose.family<CompanyLicenses, String>(
  (ref, id) => ref.watch(repositoryProvider).companyLicenses(id),
);
