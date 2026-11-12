// موديلات مدار — بتتقري من JSON اللي بترجعه الـ RPCs في schema.sql

double d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
int i(dynamic v) => v == null ? 0 : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
DateTime? t(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
String? s(dynamic v) => v?.toString();
String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
List<Map<String, dynamic>> list(dynamic v) =>
    v is List ? v.map((e) => Map<String, dynamic>.from(e as Map)).toList() : const [];

enum Role { superAdmin, manager, keeper, rep }

Role roleFrom(String? v) => switch (v) {
      'super_admin' => Role.superAdmin,
      'manager' => Role.manager,
      'keeper' => Role.keeper,
      _ => Role.rep,
    };

String roleLabel(Role r) => switch (r) {
      Role.superAdmin => 'سوبر أدمن',
      Role.manager => 'مدير الشركة',
      Role.keeper => 'أمين مخزن',
      Role.rep => 'مندوب',
    };

class Profile {
  final String id;
  final Role role;
  final String fullName;
  final String? companyId, companyName, warehouseId, warehouseName, licenseKey, deviceName;
  final DateTime? expiresAt;
  final bool allowCredit;

  const Profile({
    required this.id,
    required this.role,
    required this.fullName,
    this.companyId,
    this.companyName,
    this.warehouseId,
    this.warehouseName,
    this.licenseKey,
    this.deviceName,
    this.expiresAt,
    this.allowCredit = true,
  });

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        role: roleFrom(j['role'] as String?),
        fullName: s(j['full_name']) ?? '',
        companyId: s(j['company_id']),
        companyName: s(j['company_name']),
        warehouseId: s(j['warehouse_id']),
        warehouseName: s(j['warehouse_name']),
        licenseKey: s(j['license_key']),
        deviceName: s(j['device_name']),
        expiresAt: t(j['expires_at']),
        allowCredit: j['allow_credit'] != false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': switch (role) {
          Role.superAdmin => 'super_admin',
          Role.manager => 'manager',
          Role.keeper => 'keeper',
          Role.rep => 'rep',
        },
        'full_name': fullName,
        'company_id': companyId,
        'company_name': companyName,
        'warehouse_id': warehouseId,
        'warehouse_name': warehouseName,
        'license_key': licenseKey,
        'device_name': deviceName,
        'expires_at': expiresAt?.toUtc().toIso8601String(),
        'allow_credit': allowCredit,
      };
}

class Totals {
  final double issued, sold, cash, credit, collections, returned, remaining;
  final int invoices;
  const Totals({
    this.issued = 0,
    this.sold = 0,
    this.cash = 0,
    this.credit = 0,
    this.collections = 0,
    this.returned = 0,
    this.remaining = 0,
    this.invoices = 0,
  });
  static const zero = Totals();

  factory Totals.fromJson(Map<String, dynamic>? j) => j == null
      ? zero
      : Totals(
          issued: d(j['issued']),
          sold: d(j['sold']),
          cash: d(j['cash']),
          credit: d(j['credit']),
          collections: d(j['collections']),
          returned: d(j['returned']),
          remaining: d(j['remaining']),
          invoices: i(j['invoices']),
        );

  Totals operator +(Totals o) => Totals(
        issued: issued + o.issued,
        sold: sold + o.sold,
        cash: cash + o.cash,
        credit: credit + o.credit,
        collections: collections + o.collections,
        returned: returned + o.returned,
        remaining: remaining + o.remaining,
        invoices: invoices + o.invoices,
      );

  /// النقدية اللي مع المندوب دلوقتي
  double get cashInHand => cash + collections;
}

enum RepStatus { idle, moving, stopped, lost, pending, done }

RepStatus repStatusFrom(String? v) => switch (v) {
      'moving' => RepStatus.moving,
      'stopped' => RepStatus.stopped,
      'lost' => RepStatus.lost,
      'pending' => RepStatus.pending,
      'done' => RepStatus.done,
      _ => RepStatus.idle,
    };

class RepLive {
  final String id, name;
  final String? phone, device, sessionId, sessionStatus;
  final DateTime? startedAt, lastSeen;
  final double? lat, lng;
  final RepStatus status;
  final Totals totals;

  const RepLive({
    required this.id,
    required this.name,
    this.phone,
    this.device,
    this.sessionId,
    this.sessionStatus,
    this.startedAt,
    this.lastSeen,
    this.lat,
    this.lng,
    this.status = RepStatus.idle,
    this.totals = Totals.zero,
  });

  factory RepLive.fromJson(Map<String, dynamic> j) => RepLive(
        id: j['id'] as String,
        name: s(j['name']) ?? '',
        phone: s(j['phone']),
        device: s(j['device']),
        sessionId: s(j['session_id']),
        sessionStatus: s(j['session_status']),
        startedAt: t(j['started_at']),
        lastSeen: t(j['last_seen']),
        lat: j['lat'] == null ? null : d(j['lat']),
        lng: j['lng'] == null ? null : d(j['lng']),
        status: repStatusFrom(s(j['status'])),
        totals: Totals.fromJson(j),
      );

  bool get inField => status == RepStatus.moving || status == RepStatus.stopped || status == RepStatus.lost;
  String get initial => initialOf(name);
}

String initialOf(String name) => name.trim().isEmpty ? '؟' : String.fromCharCode(name.trim().runes.first);

class StockLine {
  final String productId, name, unit;
  final String? code, cartonUnit;
  final double price, inStock, withReps, unitsPerCarton;
  final double? cost, cartonPrice;
  const StockLine({
    required this.productId,
    required this.name,
    required this.unit,
    this.code,
    required this.price,
    required this.inStock,
    required this.withReps,
    this.cartonUnit,
    this.unitsPerCarton = 1,
    this.cost,
    this.cartonPrice,
  });
  factory StockLine.fromJson(Map<String, dynamic> j) => StockLine(
        productId: j['product_id'] as String,
        code: s(j['code']),
        name: s(j['name']) ?? '',
        unit: s(j['unit']) ?? 'عبوة',
        price: d(j['price']),
        inStock: d(j['in_stock']),
        withReps: d(j['with_reps']),
        cartonUnit: s(j['carton_unit']),
        unitsPerCarton: j['units_per_carton'] == null ? 1 : d(j['units_per_carton']),
        cost: j['cost'] == null ? null : d(j['cost']),
        cartonPrice: j['carton_price'] == null ? null : d(j['carton_price']),
      );
  bool get hasCarton => (cartonUnit ?? '').isNotEmpty && unitsPerCarton > 1;
  /// سعر الكرتونة الفعلي: المحدد مباشرة لو موجود، وإلا محسوب من سعر الوحدة × العدد.
  double get effectiveCartonPrice => cartonPrice ?? (price * unitsPerCarton);
}

/// دفعة بضاعة قربت تخلّص صلاحيتها — للتنبيه عند أمين المخزن والمدير.
class ExpiringBatch {
  final String productId, productName, unit;
  final double qty;
  final DateTime expiryDate;
  final String? supplierName, warehouseName;
  const ExpiringBatch({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.qty,
    required this.expiryDate,
    this.supplierName,
    this.warehouseName,
  });
  factory ExpiringBatch.fromJson(Map<String, dynamic> j) => ExpiringBatch(
        productId: j['product_id'] as String,
        productName: s(j['product_name']) ?? '',
        unit: s(j['unit']) ?? 'عبوة',
        qty: d(j['qty']),
        expiryDate: t(j['expiry_date'])!,
        supplierName: s(j['supplier_name']),
        warehouseName: s(j['warehouse_name']),
      );
  int get daysLeft => expiryDate.difference(DateTime.now()).inDays;
}

class FeedItem {
  final String kind, no, title, rep;
  final DateTime? at;
  final double amount;
  const FeedItem({required this.kind, required this.no, required this.title, required this.rep, this.at, required this.amount});
  factory FeedItem.fromJson(Map<String, dynamic> j) => FeedItem(
        kind: s(j['kind']) ?? 'sale',
        no: s(j['no']) ?? '',
        title: s(j['title']) ?? '',
        rep: s(j['rep']) ?? '',
        at: t(j['at']),
        amount: d(j['amount']),
      );
}

class WarehouseLive {
  final String id, name;
  final String? address, keeperName, keeperPhone, keeperDevice;
  final bool keeperActivated;
  final double? lat, lng;
  final int maxReps;
  final List<RepLive> reps;
  final List<StockLine> stock;
  final List<ExpiringBatch> expiringBatches;
  final List<FeedItem> feed;

  const WarehouseLive({
    required this.id,
    required this.name,
    this.address,
    this.keeperName,
    this.keeperPhone,
    this.keeperDevice,
    this.keeperActivated = false,
    this.lat,
    this.lng,
    this.maxReps = 0,
    this.reps = const [],
    this.stock = const [],
    this.expiringBatches = const [],
    this.feed = const [],
  });

  factory WarehouseLive.fromJson(Map<String, dynamic> j) {
    final w = Map<String, dynamic>.from(j['warehouse'] as Map);
    final k = j['keeper'] == null ? null : Map<String, dynamic>.from(j['keeper'] as Map);
    return WarehouseLive(
      id: w['id'] as String,
      name: s(w['name']) ?? '',
      address: s(w['address']),
      lat: w['lat'] == null ? null : d(w['lat']),
      lng: w['lng'] == null ? null : d(w['lng']),
      maxReps: i(w['max_reps']),
      keeperName: s(k?['name']),
      keeperPhone: s(k?['phone']),
      keeperDevice: s(k?['device']),
      keeperActivated: k?['activated'] == true,
      reps: list(j['reps']).map(RepLive.fromJson).toList(),
      stock: list(j['stock']).map(StockLine.fromJson).toList(),
      expiringBatches: list(j['expiring_batches']).map(ExpiringBatch.fromJson).toList(),
      feed: list(j['feed']).map(FeedItem.fromJson).toList(),
    );
  }

  Totals get totals => reps.fold(Totals.zero, (a, r) => a + r.totals);
  int get repsInField => reps.where((r) => r.inField).length;
}

class CustodyItem {
  final String productId, name, unit;
  final String? cartonUnit;
  final double price, issued, sold, returned, unitsPerCarton;
  const CustodyItem({
    required this.productId,
    required this.name,
    required this.unit,
    required this.price,
    required this.issued,
    required this.sold,
    required this.returned,
    this.cartonUnit,
    this.unitsPerCarton = 1,
  });
  factory CustodyItem.fromJson(Map<String, dynamic> j) => CustodyItem(
        productId: j['product_id'] as String,
        name: s(j['name']) ?? '',
        unit: s(j['unit']) ?? 'عبوة',
        price: d(j['price']),
        issued: d(j['issued']),
        sold: d(j['sold']),
        returned: d(j['returned']),
        cartonUnit: s(j['carton_unit']),
        unitsPerCarton: j['units_per_carton'] == null ? 1 : d(j['units_per_carton']),
      );
  double get available => issued - sold - returned;
  double get expectedReturn => issued - sold;
  bool get hasCarton => (cartonUnit ?? '').isNotEmpty && unitsPerCarton > 1;
}

class Settlement {
  final double issuedValue, returnedValue, missingValue, salesValue, cashSales, creditSales, collections, expectedCash, receivedCash, diff;
  const Settlement({
    required this.issuedValue,
    required this.returnedValue,
    required this.missingValue,
    required this.salesValue,
    required this.cashSales,
    required this.creditSales,
    required this.collections,
    required this.expectedCash,
    required this.receivedCash,
    required this.diff,
  });
  factory Settlement.fromJson(Map<String, dynamic> j) => Settlement(
        issuedValue: d(j['issued_value']),
        returnedValue: d(j['returned_value']),
        missingValue: d(j['missing_value']),
        salesValue: d(j['sales_value']),
        cashSales: d(j['cash_sales']),
        creditSales: d(j['credit_sales']),
        collections: d(j['collections']),
        expectedCash: d(j['expected_cash']),
        receivedCash: d(j['received_cash']),
        diff: d(j['diff']),
      );
}

class SessionData {
  final String sessionId, status, repId, repName;
  final String? issueNo;
  final DateTime? startedAt, submittedAt;
  final Totals totals;
  final List<CustodyItem> items;
  final Settlement? settlement;

  const SessionData({
    required this.sessionId,
    required this.status,
    required this.repId,
    required this.repName,
    this.issueNo,
    this.startedAt,
    this.submittedAt,
    this.totals = Totals.zero,
    this.items = const [],
    this.settlement,
  });

  factory SessionData.fromJson(Map<String, dynamic> j) => SessionData(
        sessionId: j['session_id'] as String,
        status: s(j['status']) ?? 'open',
        repId: j['rep_id'] as String,
        repName: s(j['rep_name']) ?? '',
        issueNo: s(j['issue_no']),
        startedAt: t(j['started_at']),
        submittedAt: t(j['submitted_at']),
        totals: Totals.fromJson(j['totals'] == null ? null : Map<String, dynamic>.from(j['totals'] as Map)),
        items: list(j['items']).map(CustodyItem.fromJson).toList(),
        settlement: j['settlement'] == null ? null : Settlement.fromJson(Map<String, dynamic>.from(j['settlement'] as Map)),
      );

  bool get isOpen => status == 'open';
  bool get isPending => status == 'pending';
  bool get isClosed => status == 'closed';

  /// المطلوب تسليمه لو المرتجع مطابق
  double get expectedCash => totals.cash + totals.collections;
}

class Customer {
  final String id, name;
  final String? code, phone, area, address;
  final double balance, creditLimit;
  const Customer({
    required this.id,
    required this.name,
    this.code,
    this.phone,
    this.area,
    this.address,
    this.balance = 0,
    this.creditLimit = 0,
  });
  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: j['id'] as String,
        name: s(j['name']) ?? '',
        code: s(j['code']),
        phone: s(j['phone']),
        area: s(j['area']),
        address: s(j['address']),
        balance: d(j['balance']),
        creditLimit: d(j['credit_limit']),
      );
}

class Supplier {
  final String id, name;
  final String? phone, address;
  final double balance;
  const Supplier({required this.id, required this.name, this.phone, this.address, this.balance = 0});
  factory Supplier.fromJson(Map<String, dynamic> j) => Supplier(
        id: j['id'] as String,
        name: s(j['name']) ?? '',
        phone: s(j['phone']),
        address: s(j['address']),
        balance: d(j['balance']),
      );
}

/// دفعة لمورد — سجل بتاريخها (مقابل Collection للعملاء)
class SupplierPayment {
  final String id, no;
  final double amount;
  final DateTime? at;
  const SupplierPayment({required this.id, required this.no, required this.amount, this.at});
  factory SupplierPayment.fromJson(Map<String, dynamic> j) => SupplierPayment(
        id: j['id'] as String,
        no: s(j['no']) ?? '',
        amount: d(j['amount']),
        at: t(j['created_at']),
      );
}

class IssueLine {
  final String productId;
  final double qty, price;
  const IssueLine(this.productId, this.qty, this.price);
  Map<String, dynamic> toJson() => {'product_id': productId, 'qty': qty, 'price': price};
}

/// سطر استلام بضاعة للمخزن — ممكن يحمل تاريخ إنتاج/صلاحية وسعر تكلفة خاص بالدفعة دي.
class ReceiveLine {
  final String productId;
  final double qty;
  final double? costPrice;
  final DateTime? productionDate, expiryDate;
  const ReceiveLine({required this.productId, required this.qty, this.costPrice, this.productionDate, this.expiryDate});
  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'qty': qty,
        if (costPrice != null) 'cost_price': costPrice,
        if (productionDate != null) 'production_date': ymd(productionDate!),
        if (expiryDate != null) 'expiry_date': ymd(expiryDate!),
      };
}

class SaleLine {
  final String productId;
  final double qty;
  const SaleLine(this.productId, this.qty);
  Map<String, dynamic> toJson() => {'product_id': productId, 'qty': qty};
}

class SaleResult {
  final String no;
  final double total, paid, credit;
  final bool queued;
  const SaleResult({required this.no, required this.total, required this.paid, required this.credit, this.queued = false});
}

/// نتيجة إذن استلام من مورد (إجمالي/مدفوع/آجل على المورد)
class ReceiveResult {
  final String no;
  final double total, paid, credit;
  const ReceiveResult({required this.no, required this.total, required this.paid, required this.credit});
  factory ReceiveResult.fromJson(Map<String, dynamic> j) =>
      ReceiveResult(no: s(j['no']) ?? '', total: d(j['total']), paid: d(j['paid']), credit: d(j['credit']));
}

class WarehouseSummary {
  final String id, name;
  final String? address, keeper;
  final int maxReps;
  final List<RepLive> reps;
  const WarehouseSummary({required this.id, required this.name, this.address, this.keeper, this.maxReps = 0, this.reps = const []});
  factory WarehouseSummary.fromJson(Map<String, dynamic> j) => WarehouseSummary(
        id: j['id'] as String,
        name: s(j['name']) ?? '',
        address: s(j['address']),
        keeper: s(j['keeper']),
        maxReps: i(j['max_reps']),
        reps: list(j['reps']).map(RepLive.fromJson).toList(),
      );
  Totals get totals => reps.fold(Totals.zero, (a, r) => a + r.totals);
  int get repsInField => reps.where((r) => r.inField).length;
}

class DeficitAlert {
  final String rep, warehouse;
  final double diff;
  const DeficitAlert(this.rep, this.warehouse, this.diff);
}

class CompanyOverview {
  final String companyName;
  final DateTime? expiresAt;
  final int maxReps;
  final List<WarehouseSummary> warehouses;
  final List<DeficitAlert> deficits;
  final List<ExpiringBatch> expiring;
  const CompanyOverview({
    required this.companyName,
    this.expiresAt,
    this.maxReps = 0,
    this.warehouses = const [],
    this.deficits = const [],
    this.expiring = const [],
  });
  factory CompanyOverview.fromJson(Map<String, dynamic> j) {
    final c = Map<String, dynamic>.from(j['company'] as Map);
    return CompanyOverview(
      companyName: s(c['name']) ?? '',
      expiresAt: t(c['expires_at']),
      maxReps: i(c['max_reps']),
      warehouses: list(j['warehouses']).map(WarehouseSummary.fromJson).toList(),
      deficits: list(j['alerts']).map((a) => DeficitAlert(s(a['rep']) ?? '', s(a['warehouse']) ?? '', d(a['diff']))).toList(),
      expiring: list(j['expiring']).map(ExpiringBatch.fromJson).toList(),
    );
  }
  Totals get totals => warehouses.fold(Totals.zero, (a, w) => a + w.totals);
  List<RepLive> get allReps => [for (final w in warehouses) ...w.reps];
}

class ReportItem {
  final String name;
  final double issued, sold, returned, value;
  const ReportItem(this.name, this.issued, this.sold, this.returned, this.value);
}

class ReportInvoice {
  final String no, customer;
  final DateTime? at;
  final double total, paid, credit;
  const ReportInvoice(this.no, this.customer, this.at, this.total, this.paid, this.credit);
}

class ReportDay {
  final DateTime day;
  final double sales, deficit;
  const ReportDay(this.day, this.sales, this.deficit);
}

class ReportCustomer {
  final String name;
  final double total, balance;
  const ReportCustomer(this.name, this.total, this.balance);
}

class RepReport {
  final String repName;
  final String? warehouse, device;
  final double sales, cash, credit, collections, returned, deficit;
  final int invoices, daysWorked;
  final List<ReportItem> items;
  final List<ReportInvoice> invoiceList;
  final List<ReportDay> days;
  final List<ReportCustomer> topCustomers;

  const RepReport({
    required this.repName,
    this.warehouse,
    this.device,
    this.sales = 0,
    this.cash = 0,
    this.credit = 0,
    this.collections = 0,
    this.returned = 0,
    this.deficit = 0,
    this.invoices = 0,
    this.daysWorked = 0,
    this.items = const [],
    this.invoiceList = const [],
    this.days = const [],
    this.topCustomers = const [],
  });

  factory RepReport.fromJson(Map<String, dynamic> j) {
    final r = Map<String, dynamic>.from(j['rep'] as Map);
    return RepReport(
      repName: s(r['name']) ?? '',
      warehouse: s(r['warehouse']),
      device: s(r['device']),
      sales: d(j['sales']),
      cash: d(j['cash']),
      credit: d(j['credit']),
      collections: d(j['collections']),
      returned: d(j['returned']),
      deficit: d(j['deficit']),
      invoices: i(j['invoices']),
      daysWorked: i(j['days_worked']),
      items: list(j['items']).map((e) => ReportItem(s(e['name']) ?? '', d(e['issued']), d(e['sold']), d(e['returned']), d(e['value']))).toList(),
      invoiceList: list(j['invoices_list'])
          .map((e) => ReportInvoice(s(e['no']) ?? '', s(e['customer']) ?? '', t(e['at']), d(e['total']), d(e['paid']), d(e['credit'])))
          .toList(),
      days: list(j['days']).map((e) => ReportDay(DateTime.parse('${e['day']}'), d(e['sales']), d(e['deficit']))).toList(),
      topCustomers: list(j['top_customers']).map((e) => ReportCustomer(s(e['name']) ?? '', d(e['total']), d(e['balance']))).toList(),
    );
  }
}

class ProfitDay {
  final DateTime day;
  final double revenue, cost;
  const ProfitDay(this.day, this.revenue, this.cost);
  double get profit => revenue - cost;
}

class ProfitItem {
  final String name;
  final double qty, revenue, cost;
  const ProfitItem(this.name, this.qty, this.revenue, this.cost);
  double get profit => revenue - cost;
}

/// تقرير أرباح لفترة: سعر البيع - سعر التكلفة الحقيقي (FEFO) لكل ما تم بيعه.
class ProfitReport {
  final DateTime from, to;
  final double revenue, cost;
  final List<ProfitDay> days;
  final List<ProfitItem> items;
  const ProfitReport({required this.from, required this.to, this.revenue = 0, this.cost = 0, this.days = const [], this.items = const []});
  factory ProfitReport.fromJson(Map<String, dynamic> j) => ProfitReport(
        from: DateTime.parse('${j['from']}'),
        to: DateTime.parse('${j['to']}'),
        revenue: d(j['revenue']),
        cost: d(j['cost']),
        days: list(j['days']).map((e) => ProfitDay(DateTime.parse('${e['day']}'), d(e['revenue']), d(e['cost']))).toList(),
        items: list(j['items']).map((e) => ProfitItem(s(e['name']) ?? '', d(e['qty']), d(e['revenue']), d(e['cost']))).toList(),
      );
  double get profit => revenue - cost;
}

/// سطر حركة واحد في كشف الصنف (استلام/صرف/مرتجع/بيع)
class ProductMovement {
  final String kind;
  final DateTime? at;
  final double qty;
  final String? title;
  final double? price, costPrice;
  const ProductMovement({required this.kind, this.at, required this.qty, this.title, this.price, this.costPrice});
  factory ProductMovement.fromJson(Map<String, dynamic> j) => ProductMovement(
        kind: s(j['kind']) ?? '',
        at: t(j['at']),
        qty: d(j['qty']),
        title: s(j['title']),
        price: j['price'] == null ? null : d(j['price']),
        costPrice: j['cost_price'] == null ? null : d(j['cost_price']),
      );
}

/// كشف حركة صنف واحد من البداية لحد النهارده (أو فترة محددة)
class ProductLedger {
  final String productId, productName, unit;
  final double price;
  final double? cost;
  final DateTime from, to;
  final double inStock, received, issued, returned, sold;
  final List<ProductMovement> movements;
  const ProductLedger({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.price,
    this.cost,
    required this.from,
    required this.to,
    this.inStock = 0,
    this.received = 0,
    this.issued = 0,
    this.returned = 0,
    this.sold = 0,
    this.movements = const [],
  });
  factory ProductLedger.fromJson(Map<String, dynamic> j) {
    final p = Map<String, dynamic>.from(j['product'] as Map);
    return ProductLedger(
      productId: p['id'] as String,
      productName: s(p['name']) ?? '',
      unit: s(p['unit']) ?? 'عبوة',
      price: d(p['price']),
      cost: p['cost'] == null ? null : d(p['cost']),
      from: DateTime.parse('${j['from']}'),
      to: DateTime.parse('${j['to']}'),
      inStock: d(j['in_stock']),
      received: d(j['received']),
      issued: d(j['issued']),
      returned: d(j['returned']),
      sold: d(j['sold']),
      movements: list(j['movements']).map(ProductMovement.fromJson).toList(),
    );
  }
}

class CompanyRow {
  final String id, code, name;
  final String? managerName;
  final bool active;
  final DateTime expiresAt;
  final DateTime? createdAt;
  final int warehouses, maxWarehouses, reps, maxReps, devicesActive, devicesTotal;
  const CompanyRow({
    required this.id,
    required this.code,
    required this.name,
    this.managerName,
    required this.active,
    required this.expiresAt,
    this.createdAt,
    this.warehouses = 0,
    this.maxWarehouses = 0,
    this.reps = 0,
    this.maxReps = 0,
    this.devicesActive = 0,
    this.devicesTotal = 0,
  });
  factory CompanyRow.fromJson(Map<String, dynamic> j) => CompanyRow(
        id: j['id'] as String,
        code: s(j['code']) ?? '',
        name: s(j['name']) ?? '',
        managerName: s(j['manager_name']),
        active: j['active'] == true,
        expiresAt: t(j['expires_at']) ?? DateTime.now(),
        createdAt: t(j['created_at']),
        warehouses: i(j['warehouses']),
        maxWarehouses: i(j['max_warehouses']),
        reps: i(j['reps']),
        maxReps: i(j['max_reps']),
        devicesActive: i(j['devices_active']),
        devicesTotal: i(j['devices_total']),
      );
  int get daysLeft => expiresAt.difference(DateTime.now()).inDays;
  bool get expired => expiresAt.isBefore(DateTime.now());
}

class LicenseRow {
  final String id, profileId, name, key;
  final Role role;
  final String? phone, warehouse, deviceName, deviceSerial, platform;
  final DateTime? activatedAt;
  final bool bound, active;
  const LicenseRow({
    required this.id,
    required this.profileId,
    required this.name,
    required this.key,
    required this.role,
    this.phone,
    this.warehouse,
    this.deviceName,
    this.deviceSerial,
    this.platform,
    this.activatedAt,
    required this.bound,
    required this.active,
  });
  factory LicenseRow.fromJson(Map<String, dynamic> j) => LicenseRow(
        id: j['id'] as String,
        profileId: j['profile_id'] as String,
        name: s(j['name']) ?? '',
        key: s(j['license_key']) ?? '',
        role: roleFrom(s(j['role'])),
        phone: s(j['phone']),
        warehouse: s(j['warehouse']),
        deviceName: s(j['device_name']),
        deviceSerial: s(j['device_serial']),
        platform: s(j['platform']),
        activatedAt: t(j['activated_at']),
        bound: j['bound'] == true,
        active: j['active'] == true,
      );
}

class CompanyLicenses {
  final CompanyRow company;
  final List<LicenseRow> licenses;
  final List<({String id, String name})> warehouses;
  const CompanyLicenses({required this.company, required this.licenses, this.warehouses = const []});
  factory CompanyLicenses.fromJson(Map<String, dynamic> j) => CompanyLicenses(
        company: CompanyRow.fromJson(Map<String, dynamic>.from(j['company'] as Map)),
        licenses: list(j['licenses']).map(LicenseRow.fromJson).toList(),
        warehouses: list(j['warehouses']).map((w) => (id: w['id'] as String, name: s(w['name']) ?? '')).toList(),
      );
}

enum DurationUnit { hour, day, week, month, year }

String durationUnitLabel(DurationUnit u) => switch (u) {
      DurationUnit.hour => 'ساعة',
      DurationUnit.day => 'يوم',
      DurationUnit.week => 'أسبوع',
      DurationUnit.month => 'شهر',
      DurationUnit.year => 'سنة',
    };

DateTime addDuration(DateTime from, DurationUnit u, int count) => switch (u) {
      DurationUnit.hour => from.add(Duration(hours: count)),
      DurationUnit.day => from.add(Duration(days: count)),
      DurationUnit.week => from.add(Duration(days: 7 * count)),
      DurationUnit.month => DateTime(from.year, from.month + count, from.day, from.hour, from.minute),
      DurationUnit.year => DateTime(from.year + count, from.month, from.day, from.hour, from.minute),
    };

class NewCompanyInput {
  final String name, managerName, managerPhone;
  final List<({String name, int reps})> warehouses;
  final DurationUnit unit;
  final int count;
  const NewCompanyInput({
    required this.name,
    required this.managerName,
    required this.managerPhone,
    required this.warehouses,
    required this.unit,
    required this.count,
  });
}

class CreatedAccount {
  final Role role;
  final String name, key;
  final String? warehouse;
  const CreatedAccount({required this.role, required this.name, required this.key, this.warehouse});
}

// ───────────────────────────── استيراد Excel
class ProductImport {
  final String code, name, unit;
  final double price;
  final double? cost, openingQty;
  const ProductImport({required this.code, required this.name, this.unit = 'كرتونة', required this.price, this.cost, this.openingQty});
}

class CustomerImport {
  final String name;
  final String? code, phone, area, address;
  final double creditLimit, openingBalance;
  const CustomerImport({
    required this.name,
    this.code,
    this.phone,
    this.area,
    this.address,
    this.creditLimit = 0,
    this.openingBalance = 0,
  });
}

class ImportResult {
  final int inserted, updated, skipped;
  final List<String> errors;
  const ImportResult({this.inserted = 0, this.updated = 0, this.skipped = 0, this.errors = const []});
}
