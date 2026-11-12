import 'dart:math';

import 'package:uuid/uuid.dart';

import '../core/device_identity.dart';
import 'models.dart';
import 'repository.dart';

/// وضع العرض: كل البيانات في الذاكرة، وكل العمليات شغالة فعلاً
/// (صرف، بيع، تحصيل، تسوية، تراخيص) علشان تجرّب التطبيق من غير Supabase.
///
/// مفاتيح التجربة:
///   MDR-DEMO-ADMN-0001  سوبر أدمن      (ديسكتوب)
///   MDR-DEMO-MNGR-0001  مدير الشركة    (ديسكتوب)
///   MDR-DEMO-KEEP-0001  أمين مخزن القاهرة (ديسكتوب)
///   MDR-DEMO-REP1-0001  المندوب خالد    (موبايل)
class DemoRepository implements MadarRepository {
  DemoRepository() {
    _seed();
  }

  static const demoKeys = {
    'MDR-DEMO-ADMN-0001': 'سوبر أدمن',
    'MDR-DEMO-MNGR-0001': 'مدير الشركة',
    'MDR-DEMO-KEEP-0001': 'أمين مخزن',
    'MDR-DEMO-REP1-0001': 'مندوب',
  };

  final _uuid = const Uuid();
  final _rnd = Random(7);
  int _seq = 140;

  late _Company _co;
  final _companies = <_Company>[];
  final _whs = <_Wh>[];
  final _people = <_Person>[];
  final _products = <_Product>[];
  final _stock = <String, Map<String, double>>{}; // wh → product → qty
  final _suppliers = <_Supplier>[];
  final _batches = <_Batch>[];
  final _supplierPayments = <_SupplierPayment>[];
  final _receipts = <_Receipt>[];
  final _soldLines = <_SoldLine>[];
  final _customers = <_Cust>[];
  final _sessions = <_Session>[];
  final _history = <String, List<_Day>>{}; // repId → أيام سابقة
  _Person? _me;

  String _id() => _uuid.v4();
  String _no(String p) => '$p-${(++_seq).toString().padLeft(5, '0')}';
  Future<void> _lag() => Future.delayed(const Duration(milliseconds: 250));

  // ═══════════════════════════════════════════════ seed
  void _seed() {
    final now = DateTime.now();
    _co = _Company('co1', 'CO-0007', 'النجمة للتوزيع', 'وليد سمير', true, DateTime(now.year, 12, 31, 23, 59), 3);
    _companies.addAll([
      _co,
      _Company('co2', 'CO-0008', 'الصعيد فودز', 'عادل حمدي', true, now.add(const Duration(days: 7)), 2, reps: 8, devices: 11, devicesTotal: 11, maxReps: 8),
      _Company('co3', 'CO-0009', 'الفيروز للمجمدات', 'نادر فتحي', true, now.add(const Duration(days: 18)), 2, reps: 4, devices: 5, devicesTotal: 9, maxReps: 6, whCount: 1),
      _Company('co4', 'CO-0010', 'الريف للتجارة', 'سعيد منصور', false, now.add(const Duration(days: 40)), 4, reps: 18, devices: 0, devicesTotal: 23, maxReps: 20),
      _Company('co5', 'CO-0011', 'دلتا ديستربيوشن', 'تامر رشدي', true, now.add(const Duration(days: 3)), 1, reps: 2, devices: 4, devicesTotal: 5, maxReps: 3),
    ]);

    final w1 = _Wh('w1', 'مخزن القاهرة', 'المعادي، القاهرة', 30.0444, 31.2357, 5);
    final w2 = _Wh('w2', 'مخزن الجيزة', 'الدقي، الجيزة', 30.0131, 31.2089, 4);
    final w3 = _Wh('w3', 'مخزن قنا', 'وسط البلد، قنا', 26.1551, 32.7160, 3);
    _whs.addAll([w1, w2, w3]);

    _products.addAll([
      _Product('p1', 'P-101', 'لحمة', 'كرتونة', 500),
      _Product('p2', 'P-102', 'كبدة', 'كرتونة', 350),
      _Product('p3', 'P-205', 'فراخ', 'كرتونة', 250),
    ]);
    _stock['w1'] = {'p1': 312, 'p2': 96, 'p3': 540};
    _stock['w2'] = {'p1': 280, 'p2': 150, 'p3': 400};
    _stock['w3'] = {'p1': 120, 'p2': 60, 'p3': 300};

    _suppliers.addAll([
      _Supplier('sup1', 'مزارع الدلتا', phone: '01011112222', address: 'بنها، القليوبية'),
      _Supplier('sup2', 'شركة النسيم للدواجن', phone: '01033334444', address: 'العاشر من رمضان'),
    ]);
    _batches.addAll([
      _Batch('b1', 'w1', 'p1', 312, now.subtract(const Duration(days: 20)),
          supplierId: 'sup1', productionDate: now.subtract(const Duration(days: 25)), expiryDate: now.add(const Duration(days: 4))),
      _Batch('b2', 'w1', 'p2', 96, now.subtract(const Duration(days: 10)),
          supplierId: 'sup2', productionDate: now.subtract(const Duration(days: 12)), expiryDate: now.add(const Duration(days: 18))),
      _Batch('b3', 'w2', 'p3', 400, now.subtract(const Duration(days: 5)),
          supplierId: 'sup1', productionDate: now.subtract(const Duration(days: 6)), expiryDate: now.subtract(const Duration(days: 1))),
    ]);

    _people.addAll([
      _Person('admin', 'خالد إسماعيل', Role.superAdmin, null, 'MDR-DEMO-ADMN-0001', 'ADMIN-PC', companyId: null),
      _Person('mgr', 'وليد سمير', Role.manager, null, 'MDR-DEMO-MNGR-0001', 'OFFICE-PC'),
      _Person('k1', 'سامح عبد الله', Role.keeper, 'w1', 'MDR-DEMO-KEEP-0001', 'WAREHOUSE-PC-01'),
      _Person('k2', 'هشام فؤاد', Role.keeper, 'w2', 'MDR-C2DN-H7QP-6PQ3', 'GIZA-STORE'),
      _Person('k3', 'مصطفى إسماعيل', Role.keeper, 'w3', 'MDR-Q9NA-4TRB-2KXW', 'QENA-PC'),
    ]);

    // المناديب: (id, name, wh, device, issued, sold, credit, status)
    final reps = <(String, String, String, String, List<double>, List<double>, double, String)>[
      ('r1', 'خالد مصطفى', 'w1', 'Samsung A15', [50, 20, 100], [10, 10, 16], 2500, 'moving'),
      ('r2', 'محمود سعيد', 'w1', 'Redmi Note 13', [40, 30, 72], [8, 5, 16], 750, 'moving'),
      ('r3', 'أحمد علي', 'w1', 'Sunmi L2S', [30, 20, 76], [7, 5, 11], 0, 'stopped'),
      ('r4', 'عمر حسن', 'w1', 'Samsung A25', [30, 20, 56], [4, 3, 13], 1200, 'pending'),
      ('r5', 'يوسف محمد', 'w1', 'Oppo A58', [20, 20, 52], [3, 2, 8], 0, 'lost'),
      ('r6', 'كريم عادل', 'w2', 'Samsung A35', [50, 30, 80], [20, 6, 16], 1800, 'moving'),
      ('r7', 'رامي نبيل', 'w2', 'Redmi 13C', [50, 30, 80], [18, 8, 12], 900, 'moving'),
      ('r8', 'سيد طه', 'w2', 'Sunmi V2s', [40, 20, 70], [10, 6, 14], 600, 'stopped'),
      ('r9', 'طارق منير', 'w2', 'Samsung A15', [40, 20, 60], [12, 2, 16], 1100, 'moving'),
      ('r10', 'حسام جمال', 'w3', 'Sunmi L2S', [40, 20, 60], [12, 6, 8], 0, 'moving'),
      ('r11', 'بلال حسن', 'w3', 'Realme C55', [30, 20, 52], [8, 2, 10], 0, 'moving'),
      ('r12', 'جمال رجب', 'w3', 'Infinix Hot 40', [20, 10, 40], [4, 0, 12], 0, 'stopped'),
    ];

    _customers.addAll([
      _Cust('c1', 'w1', 'C-001', 'سوبر ماركت الأمل', 'المعادي', 1200, 5000),
      _Cust('c2', 'w1', 'C-002', 'بقالة النور', 'دار السلام', 0, 3000),
      _Cust('c3', 'w1', 'C-003', 'هايبر الصفا', 'زهراء المعادي', 0, 10000),
      _Cust('c4', 'w1', 'C-004', 'بقالة الرحمة', 'البساتين', 8400, 7500),
      _Cust('c5', 'w1', 'C-005', 'ماركت الحرية', 'حلوان', 0, 3000),
      _Cust('c6', 'w1', 'C-006', 'سوبر ماركت السلام', 'المقطم', 0, 4000),
      _Cust('c7', 'w2', 'C-101', 'هايبر الدقي', 'الدقي', 0, 8000),
      _Cust('c8', 'w2', 'C-102', 'ماركت الهرم', 'الهرم', 650, 4000),
      _Cust('c9', 'w2', 'C-103', 'بقالة فيصل', 'فيصل', 0, 2000),
      _Cust('c10', 'w3', 'C-201', 'سوبر ماركت الشهيد', 'قنا', 0, 3000),
      _Cust('c11', 'w3', 'C-202', 'بقالة الصعيد', 'قنا', 0, 2000),
    ]);

    final today = DateTime(now.year, now.month, now.day, 8, 5);
    for (final r in reps) {
      final wh = _whs.firstWhere((w) => w.id == r.$3);
      final person = _Person(r.$1, r.$2, Role.rep, r.$3, r.$1 == 'r1' ? 'MDR-DEMO-REP1-0001' : _genKey(), r.$4);
      final a = _rnd.nextDouble() * 2 * pi;
      final dist = 0.01 + _rnd.nextDouble() * 0.05;
      person.lat = wh.lat + dist * sin(a);
      person.lng = wh.lng + dist * cos(a);
      person.speed = r.$8 == 'moving' ? 6 : 0;
      person.lastSeen = r.$8 == 'lost' ? now.subtract(const Duration(minutes: 14)) : now.subtract(Duration(seconds: 8 + _rnd.nextInt(50)));
      _people.add(person);

      final sess = _Session(_id(), r.$1, r.$3, _no('ISS'), today.add(Duration(minutes: _rnd.nextInt(30))));
      for (var k = 0; k < 3; k++) {
        sess.items[_products[k].id] = _Custody(_products[k].id, _products[k].price, r.$5[k]);
      }
      _fakeSales(sess, r.$6, r.$7);
      if (r.$8 == 'pending') {
        sess.status = 'pending';
        sess.submittedAt = now.subtract(const Duration(minutes: 20));
      }
      _sessions.add(sess);
      _history[r.$1] = _fakeHistory(r.$1, r.$6);
    }
  }

  String _genKey() {
    const a = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    String g() => List.generate(4, (_) => a[_rnd.nextInt(a.length)]).join();
    return 'MDR-${g()}-${g()}-${g()}';
  }

  void _fakeSales(_Session sess, List<double> sold, double creditTarget) {
    final custs = _customers.where((c) => c.whId == sess.whId).toList();
    var at = sess.startedAt.add(const Duration(minutes: 40));
    var creditLeft = creditTarget;
    // كل صنف بيتقسم على فواتير صغيرة
    final remaining = List<double>.from(sold);
    var n = 0;
    while (remaining.any((q) => q > 0)) {
      final lines = <String, double>{};
      for (var k = 0; k < 3; k++) {
        if (remaining[k] <= 0) continue;
        final q = min(remaining[k], (1 + _rnd.nextInt(4)).toDouble());
        lines[_products[k].id] = q;
        remaining[k] -= q;
      }
      final total = lines.entries.fold<double>(0, (a, e) => a + e.value * sess.items[e.key]!.price);
      final credit = min(creditLeft, (n.isOdd ? (total / 2).floorToDouble() : 0).toDouble());
      creditLeft -= credit;
      lines.forEach((p, q) => sess.items[p]!.sold += q);
      sess.sales.add(_Sale(_no('INV'), custs[n % custs.length].id, at, lines, total, total - credit, credit));
      at = at.add(Duration(minutes: 18 + _rnd.nextInt(25)));
      n++;
    }
    if (creditLeft > 0 && sess.sales.isNotEmpty) {
      final last = sess.sales.last;
      final c = min(creditLeft, last.paid);
      last.credit += c;
      last.paid -= c;
    }
  }

  List<_Day> _fakeHistory(String repId, List<double> soldToday) {
    final now = DateTime.now();
    final days = <_Day>[];
    final base = soldToday[0] * 500 + soldToday[1] * 350 + soldToday[2] * 250;
    for (var k = 35; k >= 1; k--) {
      final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: k));
      if (day.weekday == DateTime.friday) continue;
      final f = 1.6 + _rnd.nextDouble() * 1.1;
      final p1 = (soldToday[0] * f).roundToDouble(), p2 = (soldToday[1] * f).roundToDouble(), p3 = (soldToday[2] * f).roundToDouble();
      final sales = p1 * 500 + p2 * 350 + p3 * 250;
      final credit = (sales * (_rnd.nextDouble() * 0.08)).roundToDouble();
      final deficit = _rnd.nextInt(9) == 0 ? -(50 + _rnd.nextInt(4) * 50).toDouble() : 0.0;
      days.add(_Day(day, sales == 0 ? base : sales, sales - credit, credit, deficit, {'p1': p1, 'p2': p2, 'p3': p3}, 12 + _rnd.nextInt(14)));
    }
    return days;
  }

  // ═══════════════════════════════════════════════ helpers
  _Person _person(String id) => _people.firstWhere((p) => p.id == id);
  _Wh _wh(String id) => _whs.firstWhere((w) => w.id == id);
  _Product _product(String id) => _products.firstWhere((p) => p.id == id);
  _Person get _self => _me ?? (throw const AppException('NO_PROFILE'));

  _Session? _currentSession(String repId) {
    final now = DateTime.now();
    final list = _sessions.where((s) => s.repId == repId && (s.status != 'closed' || _sameDay(s.startedAt, now))).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return list.isEmpty ? null : list.first;
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Totals _totals(_Session? s) {
    if (s == null) return Totals.zero;
    final live = s.sales.where((x) => !x.voided);
    return Totals(
      issued: s.items.values.fold<double>(0, (a, c) => a + c.issued * c.price),
      sold: live.fold<double>(0, (a, x) => a + x.total),
      cash: live.fold<double>(0, (a, x) => a + x.paid),
      credit: live.fold<double>(0, (a, x) => a + x.credit),
      collections: s.collections.fold<double>(0, (a, x) => a + x.amount),
      returned: s.items.values.fold<double>(0, (a, c) => a + c.returned * c.price),
      remaining: s.items.values.fold<double>(0, (a, c) => a + (c.issued - c.sold - c.returned) * c.price),
      invoices: live.length,
    );
  }

  RepLive _repLive(_Person p) {
    final s = _currentSession(p.id);
    final now = DateTime.now();
    RepStatus status;
    if (s == null) {
      status = RepStatus.idle;
    } else if (s.status == 'closed') {
      status = RepStatus.done;
    } else if (s.status == 'pending') {
      status = RepStatus.pending;
    } else if (p.lastSeen == null || now.difference(p.lastSeen!).inMinutes >= 10) {
      status = RepStatus.lost;
    } else {
      status = p.speed < 0.5 ? RepStatus.stopped : RepStatus.moving;
    }
    return RepLive(
      id: p.id,
      name: p.name,
      phone: p.phone,
      device: p.device,
      sessionId: s?.id,
      sessionStatus: s?.status,
      startedAt: s?.startedAt,
      lastSeen: p.lastSeen,
      lat: p.lat,
      lng: p.lng,
      status: status,
      totals: _totals(s),
    );
  }

  SessionData _sessionJson(_Session s) => SessionData(
        sessionId: s.id,
        status: s.status,
        repId: s.repId,
        repName: _person(s.repId).name,
        issueNo: s.issueNo,
        startedAt: s.startedAt,
        submittedAt: s.submittedAt,
        totals: _totals(s),
        items: [
          for (final c in s.items.values)
            CustodyItem(
              productId: c.productId,
              name: _product(c.productId).name,
              unit: _product(c.productId).unit,
              price: c.price,
              issued: c.issued,
              sold: c.sold,
              returned: c.returned,
              cartonUnit: _product(c.productId).cartonUnit,
              unitsPerCarton: _product(c.productId).unitsPerCarton,
            )
        ],
        settlement: s.settlement,
      );

  Profile _profileOf(_Person p) {
    final wh = p.whId == null ? null : _wh(p.whId!);
    return Profile(
      id: p.id,
      role: p.role,
      fullName: p.name,
      companyId: p.role == Role.superAdmin ? null : _co.id,
      companyName: p.role == Role.superAdmin ? null : _co.name,
      warehouseId: p.whId,
      warehouseName: wh?.name,
      licenseKey: p.key,
      deviceName: p.device,
      expiresAt: _co.expiresAt,
    );
  }

  void _assertActive(_Person p) {
    if (!p.active) throw const AppException('USER_SUSPENDED');
    if (p.role != Role.superAdmin) {
      if (!_co.active) throw const AppException('COMPANY_SUSPENDED');
      if (_co.expiresAt.isBefore(DateTime.now())) throw const AppException('LICENSE_EXPIRED');
    }
  }

  // ═══════════════════════════════════════════════ الترخيص
  @override
  Future<Activation> activate(String key, DeviceIdentity device) async {
    await _lag();
    final k = key.trim().toUpperCase();
    final p = _people.where((x) => x.key == k).firstOrNull;
    if (p == null) throw const AppException('INVALID_KEY');
    if (p.fingerprint != null && p.fingerprint != device.fingerprint) throw const AppException('ALREADY_BOUND');
    _assertActive(p);
    p
      ..fingerprint = device.fingerprint
      ..device = device.deviceName
      ..serial = device.serial
      ..activatedAt = DateTime.now();
    _me = p;
    return Activation(_profileOf(p), {'key': k});
  }

  @override
  Future<Profile> restore(Map<String, String> credentials, DeviceIdentity device) async {
    await _lag();
    final p = _people.where((x) => x.key == credentials['key']).firstOrNull;
    if (p == null) throw const AppException('UNBOUND');
    // وضع العرض بيبدأ من جديد مع كل تشغيل، فالربط بيتعمل تاني تلقائياً
    p.fingerprint ??= device.fingerprint;
    if (p.fingerprint != device.fingerprint) throw const AppException('OTHER_DEVICE');
    _assertActive(p);
    _me = p;
    return _profileOf(p);
  }

  @override
  Future<Profile> verify(DeviceIdentity device) async {
    final p = _self;
    if (p.fingerprint == null) throw const AppException('UNBOUND');
    if (p.fingerprint != device.fingerprint) throw const AppException('OTHER_DEVICE');
    _assertActive(p);
    return _profileOf(p);
  }

  // ═══════════════════════════════════════════════ أمين المخزن + المدير
  @override
  Future<WarehouseLive> warehouseLive([String? warehouseId]) async {
    await _lag();
    final w = _wh(warehouseId ?? _self.whId!);
    final keeper = _people.where((p) => p.role == Role.keeper && p.whId == w.id).firstOrNull;
    final reps = _people.where((p) => p.role == Role.rep && p.whId == w.id).map(_repLive).toList()
      ..sort((a, b) => b.totals.sold.compareTo(a.totals.sold));
    final now = DateTime.now();
    final open = _sessions.where((s) => s.whId == w.id && s.status != 'closed');
    final feed = <FeedItem>[
      for (final s in _sessions.where((s) => s.whId == w.id && _sameDay(s.startedAt, now))) ...[
        FeedItem(kind: 'issue', no: s.issueNo, title: _person(s.repId).name, rep: _person(s.repId).name, at: s.startedAt, amount: _totals(s).issued),
        for (final x in s.sales)
          FeedItem(kind: 'sale', no: x.no, title: _cust(x.customerId).name, rep: _person(s.repId).name, at: x.at, amount: x.total),
        for (final x in s.collections)
          FeedItem(kind: 'collection', no: x.no, title: _cust(x.customerId).name, rep: _person(s.repId).name, at: x.at, amount: x.amount),
      ]
    ]..sort((a, b) => b.at!.compareTo(a.at!));
    return WarehouseLive(
      id: w.id,
      name: w.name,
      address: w.address,
      lat: w.lat,
      lng: w.lng,
      maxReps: w.maxReps,
      keeperName: keeper?.name,
      keeperPhone: keeper?.phone,
      keeperDevice: keeper?.device,
      keeperActivated: keeper?.fingerprint != null || keeper != null,
      reps: reps,
      stock: [
        for (final p in _products.where((p) => p.active))
          StockLine(
            productId: p.id,
            code: p.code,
            name: p.name,
            unit: p.unit,
            price: p.price,
            cost: p.cost,
            inStock: _stock[w.id]?[p.id] ?? 0,
            withReps: open.fold<double>(0, (a, s) {
              final c = s.items[p.id];
              return a + (c == null ? 0 : c.issued - c.sold - c.returned);
            }),
            cartonUnit: p.cartonUnit,
            unitsPerCarton: p.unitsPerCarton,
            cartonPrice: p.cartonPrice,
          )
      ],
      expiringBatches: _expiringBatches(w.id),
      feed: feed.take(12).toList(),
    );
  }

  /// يخصم من الدفعات بالأقرب للانتهاء أولاً (FEFO) ويرجّع متوسط سعر التكلفة الحقيقي
  /// للكمية المتاخدة — من غير ما يفشل لو الدفعات مش كافية (بيكمّل بسعر الصنف المرجعي).
  double _drainBatchesFefo(String whId, String productId, double qty) {
    var remaining = qty;
    var costSum = 0.0;
    final rows = _batches.where((b) => b.whId == whId && b.productId == productId && b.qty > 0).toList()
      ..sort((a, b) {
        final ea = a.expiryDate, eb = b.expiryDate;
        if (ea == null && eb == null) return a.createdAt.compareTo(b.createdAt);
        if (ea == null) return 1;
        if (eb == null) return -1;
        return ea.compareTo(eb);
      });
    for (final b in rows) {
      if (remaining <= 0) break;
      final take = min(b.qty, remaining);
      b.qty -= take;
      costSum += take * b.costPrice;
      remaining -= take;
    }
    if (remaining > 0) {
      costSum += remaining * (_product(productId).cost ?? 0);
    }
    return qty > 0 ? costSum / qty : 0;
  }

  List<ExpiringBatch> _expiringBatches(String whId) {
    final cutoff = DateTime.now().add(const Duration(days: 30));
    final rows = _batches.where((b) => b.whId == whId && b.qty > 0 && b.expiryDate != null && !b.expiryDate!.isAfter(cutoff)).toList()
      ..sort((a, b) => a.expiryDate!.compareTo(b.expiryDate!));
    return [
      for (final b in rows)
        ExpiringBatch(
          productId: b.productId,
          productName: _product(b.productId).name,
          unit: _product(b.productId).unit,
          qty: b.qty,
          expiryDate: b.expiryDate!,
          supplierName: b.supplierId == null ? null : _suppliers.where((s) => s.id == b.supplierId).firstOrNull?.name,
          warehouseName: _wh(whId).name,
        )
    ];
  }

  _Cust _cust(String id) => _customers.firstWhere((c) => c.id == id);

  @override
  Future<String> createStockIssue(String repId, List<IssueLine> lines) async {
    await _lag();
    final me = _self;
    if (me.role != Role.keeper) throw const AppException('ONLY_KEEPER');
    final rep = _person(repId);
    if (rep.whId != me.whId) throw const AppException('REP_NOT_IN_WAREHOUSE');
    if (_sessions.any((s) => s.repId == repId && s.status != 'closed')) throw const AppException('REP_HAS_OPEN_SESSION');
    if (lines.isEmpty) throw const AppException('EMPTY_ISSUE');
    // الصرف من غير التقيد برصيد المخزن — ممكن يعدي صفر أو يفضل سالب.
    final stock = _stock[me.whId]!;
    final s = _Session(_id(), repId, me.whId!, _no('ISS'), DateTime.now());
    for (final l in lines) {
      stock[l.productId] = (stock[l.productId] ?? 0) - l.qty;
      final unitCost = _drainBatchesFefo(me.whId!, l.productId, l.qty);
      s.items[l.productId] = _Custody(l.productId, l.price, l.qty, costPrice: unitCost);
    }
    _sessions.add(s);
    rep
      ..lastSeen = DateTime.now()
      ..speed = 0;
    return s.issueNo;
  }

  @override
  Future<SessionData> sessionData(String sessionId) async {
    await _lag();
    return _sessionJson(_sessions.firstWhere((s) => s.id == sessionId));
  }

  @override
  Future<SessionData> approveSettlement(String sessionId, Map<String, double> returns, double receivedCash) async {
    await _lag();
    final me = _self;
    if (me.role != Role.keeper) throw const AppException('ONLY_KEEPER');
    final s = _sessions.firstWhere((x) => x.id == sessionId);
    if (s.status == 'closed') throw const AppException('ALREADY_CLOSED');
    for (final c in s.items.values) {
      final r = returns[c.productId] ?? (c.issued - c.sold);
      if (r < 0 || r > c.issued - c.sold) throw const AppException('BAD_RETURN_QTY');
      c.returned = r;
      _stock[s.whId]![c.productId] = (_stock[s.whId]![c.productId] ?? 0) + r;
    }
    final t = _totals(s);
    final missing = s.items.values.fold<double>(0, (a, c) => a + (c.issued - c.sold - c.returned) * c.price);
    final expected = t.cash + t.collections + missing;
    s.settlement = Settlement(
      issuedValue: t.issued,
      returnedValue: t.returned,
      missingValue: missing,
      salesValue: t.sold,
      cashSales: t.cash,
      creditSales: t.credit,
      collections: t.collections,
      expectedCash: expected,
      receivedCash: receivedCash,
      diff: receivedCash - expected,
    );
    s.status = 'closed';
    return _sessionJson(s);
  }

  @override
  Future<void> upsertProduct({
    String? id,
    required String code,
    required String name,
    required String unit,
    required double price,
    String? cartonUnit,
    double unitsPerCarton = 1,
    double? cost,
    double? cartonPrice,
    double? openingQty,
  }) async {
    await _lag();
    final cu = (cartonUnit ?? '').isEmpty ? null : cartonUnit;
    final upc = unitsPerCarton <= 0 ? 1.0 : unitsPerCarton;
    if (id == null) {
      final p = _Product(_id(), code, name, unit, price, cost: cost, cartonUnit: cu, unitsPerCarton: upc, cartonPrice: cartonPrice);
      _products.add(p);
      if (openingQty != null && openingQty > 0) {
        await receiveStock([ReceiveLine(productId: p.id, qty: openingQty, costPrice: cost)]);
      }
    } else {
      final p = _product(id);
      p
        ..code = code
        ..name = name
        ..unit = unit
        ..price = price
        ..cost = cost
        ..cartonUnit = cu
        ..unitsPerCarton = upc
        ..cartonPrice = cartonPrice;
    }
  }

  @override
  Future<ReceiveResult> receiveStock(List<ReceiveLine> lines, {String? supplierId, double? paid}) async {
    await _lag();
    final whId = _self.whId!;
    final st = _stock[whId]!;
    final now = DateTime.now();
    var total = 0.0;
    for (final l in lines) {
      if (l.qty <= 0) continue;
      final cost = l.costPrice ?? _product(l.productId).cost ?? 0;
      st[l.productId] = (st[l.productId] ?? 0) + l.qty;
      _batches.add(_Batch(_id(), whId, l.productId, l.qty, now,
          supplierId: supplierId, productionDate: l.productionDate, expiryDate: l.expiryDate, costPrice: cost));
      _receipts.add(_Receipt(whId, l.productId, supplierId, l.qty, cost, now));
      total += l.qty * cost;
    }
    final no = _no('REC');
    if (supplierId == null) return ReceiveResult(no: no, total: total, paid: total, credit: 0);
    final p = (paid ?? total).clamp(0, total).toDouble();
    final credit = total - p;
    if (credit > 0) _suppliers.firstWhere((s) => s.id == supplierId).balance += credit;
    return ReceiveResult(no: no, total: total, paid: p, credit: credit);
  }

  @override
  Future<List<Customer>> customers() async {
    await _lag();
    final me = _self;
    return _customers
        .where((c) => me.role == Role.manager || c.whId == me.whId)
        .map((c) => Customer(id: c.id, name: c.name, code: c.code, area: c.area, balance: c.balance, creditLimit: c.limit))
        .toList();
  }

  @override
  Future<void> addCustomer({
    required String name,
    String? phone,
    String? area,
    String? code,
    double creditLimit = 0,
    double openingBalance = 0,
  }) async {
    await _lag();
    _customers.add(_Cust(_id(), _self.whId ?? 'w1', code ?? 'C-${_customers.length + 1}', name, area ?? '', openingBalance, creditLimit));
  }

  @override
  Future<List<Supplier>> suppliers() async {
    await _lag();
    return _suppliers.map((s) => Supplier(id: s.id, name: s.name, phone: s.phone, address: s.address, balance: s.balance)).toList();
  }

  @override
  Future<void> upsertSupplier({String? id, required String name, String? phone, String? address, double openingBalance = 0}) async {
    await _lag();
    if (id == null) {
      _suppliers.add(_Supplier(_id(), name, phone: phone, address: address)..balance = openingBalance);
    } else {
      final sup = _suppliers.firstWhere((s) => s.id == id);
      sup
        ..name = name
        ..phone = phone
        ..address = address;
    }
  }

  @override
  Future<List<SupplierPayment>> supplierPayments(String supplierId) async {
    await _lag();
    final rows = _supplierPayments.where((p) => p.supplierId == supplierId).toList()..sort((a, b) => b.at.compareTo(a.at));
    return rows.map((p) => SupplierPayment(id: p.id, no: p.no, amount: p.amount, at: p.at)).toList();
  }

  @override
  Future<void> createSupplierPayment(String clientUuid, String supplierId, double amount) async {
    await _lag();
    if (_supplierPayments.any((p) => p.id == clientUuid)) return;
    _supplierPayments.add(_SupplierPayment(clientUuid, _no('PAY'), supplierId, amount, DateTime.now()));
    _suppliers.firstWhere((s) => s.id == supplierId).balance -= amount;
  }

  @override
  Future<ImportResult> importProducts(List<ProductImport> rows) async {
    await _lag();
    var ins = 0, upd = 0, skip = 0;
    for (final r in rows) {
      if (r.code.isEmpty || r.name.isEmpty) {
        skip++;
        continue;
      }
      var p = _products.where((x) => x.code == r.code).firstOrNull;
      if (p == null) {
        p = _Product(_id(), r.code, r.name, r.unit, r.price);
        _products.add(p);
        ins++;
      } else {
        p
          ..name = r.name
          ..unit = r.unit
          ..price = r.price
          ..active = true;
        upd++;
      }
      final q = r.openingQty ?? 0;
      if (q > 0 && _self.role == Role.keeper) {
        final st = _stock[_self.whId]!;
        st[p.id] = (st[p.id] ?? 0) + q;
      }
    }
    return ImportResult(inserted: ins, updated: upd, skipped: skip);
  }

  @override
  Future<ImportResult> importCustomers(List<CustomerImport> rows) async {
    await _lag();
    if (_self.role != Role.keeper) throw const AppException('ONLY_KEEPER');
    var ins = 0, upd = 0, skip = 0;
    for (final r in rows) {
      if (r.name.isEmpty) {
        skip++;
        continue;
      }
      final hit = _customers
          .where((c) => r.code != null && r.code!.isNotEmpty ? c.code == r.code : (c.name == r.name && c.whId == _self.whId))
          .firstOrNull;
      if (hit == null) {
        _customers.add(_Cust(_id(), _self.whId!, r.code ?? '', r.name, r.area ?? '', r.openingBalance, r.creditLimit));
        ins++;
      } else {
        hit.limit = r.creditLimit;
        upd++;
      }
    }
    return ImportResult(inserted: ins, updated: upd, skipped: skip);
  }

  // ═══════════════════════════════════════════════ المندوب
  @override
  Future<SessionData?> myCustody() async {
    await _lag();
    final s = _sessions.where((x) => x.repId == _self.id && x.status != 'closed').firstOrNull;
    return s == null ? null : _sessionJson(s);
  }

  @override
  Future<SaleResult> createSale(String clientUuid, String customerId, List<SaleLine> lines, double paid) async {
    await _lag();
    final s = _sessions.where((x) => x.repId == _self.id && x.status == 'open').firstOrNull;
    if (s == null) throw const AppException('NO_OPEN_SESSION');
    final dup = s.sales.where((x) => x.clientUuid == clientUuid).firstOrNull;
    if (dup != null) return SaleResult(no: dup.no, total: dup.total, paid: dup.paid, credit: dup.credit);
    if (lines.isEmpty) throw const AppException('EMPTY_SALE');
    var total = 0.0;
    for (final l in lines) {
      final c = s.items[l.productId];
      if (c == null) throw const AppException('NOT_IN_CUSTODY');
      if (l.qty > c.issued - c.sold - c.returned) throw AppException('EXCEEDS_CUSTODY', _product(l.productId).name);
      total += l.qty * c.price;
    }
    final now = DateTime.now();
    for (final l in lines) {
      final c = s.items[l.productId]!;
      c.sold += l.qty;
      _soldLines.add(_SoldLine(s.whId, l.productId, customerId, l.qty, c.price, c.costPrice, now));
    }
    final p = paid.clamp(0, total).toDouble();
    final sale = _Sale(_no('INV'), customerId, now, {for (final l in lines) l.productId: l.qty}, total, p, total - p)
      ..clientUuid = clientUuid;
    s.sales.add(sale);
    _cust(customerId).balance += total - p;
    return SaleResult(no: sale.no, total: total, paid: p, credit: total - p);
  }

  @override
  Future<void> createCollection(String clientUuid, String customerId, double amount) async {
    await _lag();
    final s = _sessions.where((x) => x.repId == _self.id && x.status == 'open').firstOrNull;
    if (s == null) throw const AppException('NO_OPEN_SESSION');
    if (s.collections.any((c) => c.clientUuid == clientUuid)) return;
    s.collections.add(_Coll(_no('COL'), customerId, DateTime.now(), amount, clientUuid));
    _cust(customerId).balance -= amount;
  }

  @override
  Future<void> submitDayEnd() async {
    await _lag();
    for (final s in _sessions.where((x) => x.repId == _self.id && x.status == 'open')) {
      s
        ..status = 'pending'
        ..submittedAt = DateTime.now();
    }
  }

  @override
  Future<void> pushLocation(double lat, double lng, double? accuracy, double? speed) async {
    final p = _self;
    p
      ..lat = lat
      ..lng = lng
      ..speed = speed ?? 0
      ..lastSeen = DateTime.now();
  }

  // ═══════════════════════════════════════════════ المدير
  @override
  Future<CompanyOverview> companyOverview() async {
    await _lag();
    return CompanyOverview(
      companyName: _co.name,
      expiresAt: _co.expiresAt,
      maxReps: _whs.fold(0, (a, w) => a + w.maxReps),
      warehouses: [
        for (final w in _whs)
          WarehouseSummary(
            id: w.id,
            name: w.name,
            address: w.address,
            keeper: _people.where((p) => p.role == Role.keeper && p.whId == w.id).firstOrNull?.name,
            maxReps: w.maxReps,
            reps: _people.where((p) => p.role == Role.rep && p.whId == w.id).map(_repLive).toList(),
          )
      ],
      deficits: [
        for (final s in _sessions.where((s) => s.settlement != null && s.settlement!.diff < 0))
          DeficitAlert(_person(s.repId).name, _wh(s.whId).name, s.settlement!.diff),
        const DeficitAlert('خالد مصطفى', 'مخزن القاهرة', -200),
      ],
      expiring: [for (final w in _whs) ..._expiringBatches(w.id)]..sort((a, b) => a.expiryDate.compareTo(b.expiryDate)),
    );
  }

  @override
  Future<RepReport> repReport(String repId, DateTime from, DateTime to) async {
    await _lag();
    final rep = _person(repId);
    final f = DateTime(from.year, from.month, from.day);
    final tt = DateTime(to.year, to.month, to.day, 23, 59);
    bool inRange(DateTime d) => !d.isBefore(f) && !d.isAfter(tt);

    final days = <ReportDay>[];
    var sales = 0.0, cash = 0.0, credit = 0.0, deficit = 0.0, returned = 0.0, collections = 0.0;
    var invoices = 0;
    final itemSold = <String, double>{}, itemIssued = <String, double>{}, itemReturned = <String, double>{};
    final invoiceList = <ReportInvoice>[];
    final custTotals = <String, double>{};

    for (final h in _history[repId] ?? const <_Day>[]) {
      if (!inRange(h.day)) continue;
      days.add(ReportDay(h.day, h.sales, h.deficit));
      sales += h.sales;
      cash += h.cash;
      credit += h.credit;
      deficit += h.deficit;
      invoices += h.invoices;
      h.items.forEach((p, q) {
        itemSold[p] = (itemSold[p] ?? 0) + q;
        itemIssued[p] = (itemIssued[p] ?? 0) + (q * 1.6).roundToDouble();
        itemReturned[p] = (itemReturned[p] ?? 0) + (q * 0.6).roundToDouble();
      });
      returned += h.sales * 0.6;
    }
    for (final s in _sessions.where((s) => s.repId == repId && inRange(s.startedAt))) {
      final t = _totals(s);
      days.add(ReportDay(DateTime(s.startedAt.year, s.startedAt.month, s.startedAt.day), t.sold, min(0.0, s.settlement?.diff ?? 0.0)));
      sales += t.sold;
      cash += t.cash;
      credit += t.credit;
      collections += t.collections;
      returned += t.returned;
      deficit += min(0.0, s.settlement?.diff ?? 0.0);
      invoices += t.invoices;
      for (final c in s.items.values) {
        itemSold[c.productId] = (itemSold[c.productId] ?? 0) + c.sold;
        itemIssued[c.productId] = (itemIssued[c.productId] ?? 0) + c.issued;
        itemReturned[c.productId] = (itemReturned[c.productId] ?? 0) + c.returned;
      }
      for (final x in s.sales.reversed) {
        invoiceList.add(ReportInvoice(x.no, _cust(x.customerId).name, x.at, x.total, x.paid, x.credit));
        custTotals[x.customerId] = (custTotals[x.customerId] ?? 0) + x.total;
      }
    }
    days.sort((a, b) => a.day.compareTo(b.day));
    if (custTotals.isEmpty) {
      for (final c in _customers.where((c) => c.whId == rep.whId).take(5)) {
        custTotals[c.id] = sales * (0.08 + _rnd.nextDouble() * 0.1);
      }
    }
    final top = custTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return RepReport(
      repName: rep.name,
      warehouse: rep.whId == null ? null : _wh(rep.whId!).name,
      device: rep.device,
      sales: sales,
      cash: cash,
      credit: credit,
      collections: collections,
      returned: returned,
      deficit: deficit,
      invoices: invoices,
      daysWorked: days.length,
      items: [
        for (final p in _products)
          if ((itemSold[p.id] ?? 0) > 0 || (itemIssued[p.id] ?? 0) > 0)
            ReportItem(p.name, itemIssued[p.id] ?? 0, itemSold[p.id] ?? 0, itemReturned[p.id] ?? 0, (itemSold[p.id] ?? 0) * p.price)
      ]..sort((a, b) => b.value.compareTo(a.value)),
      invoiceList: invoiceList,
      days: days,
      topCustomers: [
        for (final e in top.take(5)) ReportCustomer(_cust(e.key).name, e.value.roundToDouble(), _cust(e.key).balance),
      ],
    );
  }

  // ═══════════════════════════════════════════════ السوبر أدمن
  @override
  Future<List<CompanyRow>> companies() async {
    await _lag();
    return [
      for (final c in _companies)
        CompanyRow(
          id: c.id,
          code: c.code,
          name: c.name,
          managerName: c.manager,
          active: c.active,
          expiresAt: c.expiresAt,
          warehouses: c == _co ? _whs.length : c.whCount ?? c.maxWh,
          maxWarehouses: c.maxWh,
          reps: c == _co ? _people.where((p) => p.role == Role.rep).length : c.reps,
          maxReps: c == _co ? _whs.fold(0, (a, w) => a + w.maxReps) : c.maxReps,
          devicesActive: c == _co ? _people.where((p) => p.role != Role.superAdmin && p.fingerprint != null && p.active).length : c.devices,
          devicesTotal: c == _co ? _people.where((p) => p.role != Role.superAdmin).length : c.devicesTotal,
        )
    ];
  }

  _Company _company(String id) => _companies.firstWhere((c) => c.id == id);

  @override
  Future<void> setCompanyActive(String companyId, bool active) async {
    await _lag();
    _company(companyId).active = active;
  }

  @override
  Future<DateTime> extendCompany(String companyId, DurationUnit unit, int count) async {
    await _lag();
    final c = _company(companyId);
    final from = c.expiresAt.isBefore(DateTime.now()) ? DateTime.now() : c.expiresAt;
    c.expiresAt = addDuration(from, unit, count);
    return c.expiresAt;
  }

  @override
  Future<CompanyLicenses> companyLicenses(String companyId) async {
    await _lag();
    final c = _company(companyId);
    final row = (await companies()).firstWhere((r) => r.id == companyId);
    if (c != _co) {
      // شركات العرض التانية: حسابات مولّدة
      c.people ??= [
        _Person('${c.id}-m', c.manager, Role.manager, null, _genKey(), 'OFFICE-PC'),
        for (var k = 1; k <= c.reps; k++) _Person('${c.id}-r$k', 'مندوب $k', Role.rep, null, _genKey(), k.isOdd ? 'Samsung A15' : null),
      ];
      return CompanyLicenses(company: row, licenses: [for (final p in c.people!) _licenseRow(p)]);
    }
    final ppl = _people.where((p) => p.role != Role.superAdmin).toList()
      ..sort((a, b) => a.role.index.compareTo(b.role.index));
    return CompanyLicenses(
      company: row,
      licenses: [for (final p in ppl) _licenseRow(p)],
      warehouses: [for (final w in _whs) (id: w.id, name: w.name)],
    );
  }

  LicenseRow _licenseRow(_Person p) => LicenseRow(
        id: p.id,
        profileId: p.id,
        name: p.name,
        key: p.key,
        role: p.role,
        phone: p.phone,
        warehouse: p.whId == null ? (p.role == Role.manager ? 'كل المخازن' : null) : _wh(p.whId!).name,
        deviceName: p.device,
        deviceSerial: p.serial,
        activatedAt: p.activatedAt,
        bound: p.device != null,
        active: p.active,
      );

  _Person _anyPerson(String id) {
    for (final c in _companies) {
      final hit = c.people?.where((p) => p.id == id).firstOrNull;
      if (hit != null) return hit;
    }
    return _person(id);
  }

  @override
  Future<void> setLicenseActive(String licenseId, bool active) async {
    await _lag();
    _anyPerson(licenseId).active = active;
  }

  @override
  Future<void> unbindLicense(String licenseId) async {
    await _lag();
    _anyPerson(licenseId)
      ..fingerprint = null
      ..device = null
      ..serial = null
      ..activatedAt = null;
  }

  @override
  Future<String> regenerateKey(String licenseId) async {
    await _lag();
    final p = _anyPerson(licenseId);
    if (p.key.startsWith('MDR-DEMO')) return p.key; // مفاتيح التجربة ثابتة
    p
      ..key = _genKey()
      ..fingerprint = null
      ..device = null
      ..serial = null;
    return p.key;
  }

  @override
  Future<List<CreatedAccount>> createCompany(NewCompanyInput input) async {
    await _lag();
    final c = _Company(_id(), 'CO-${(12 + _companies.length).toString().padLeft(4, '0')}', input.name, input.managerName, true,
        addDuration(DateTime.now(), input.unit, input.count), input.warehouses.length,
        reps: input.warehouses.fold(0, (a, w) => a + w.reps), devices: 0, maxReps: input.warehouses.fold(0, (a, w) => a + w.reps));
    final accounts = <CreatedAccount>[CreatedAccount(role: Role.manager, name: input.managerName, key: _genKey())];
    for (final w in input.warehouses) {
      accounts.add(CreatedAccount(role: Role.keeper, name: 'أمين ${w.name}', key: _genKey(), warehouse: w.name));
      for (var k = 1; k <= w.reps; k++) {
        accounts.add(CreatedAccount(role: Role.rep, name: 'مندوب $k — ${w.name}', key: _genKey(), warehouse: w.name));
      }
    }
    c.devicesTotal = accounts.length;
    c.people = [
      for (final a in accounts) _Person(_id(), a.name, a.role, null, a.key, null),
    ];
    _companies.insert(1, c);
    return accounts;
  }

  @override
  Future<CreatedAccount> addAccount({required String companyId, String? warehouseId, required Role role, required String name}) async {
    await _lag();
    final p = _Person(_id(), name, role, companyId == _co.id ? warehouseId : null, _genKey(), null);
    if (companyId == _co.id) {
      _people.add(p);
    } else {
      (_company(companyId).people ??= []).add(p);
    }
    return CreatedAccount(role: role, name: name, key: p.key);
  }

  @override
  Future<void> renameAccount(String profileId, String name, {String? phone}) async {
    await _lag();
    final p = _anyPerson(profileId);
    p.name = name;
    p.phone = phone;
  }

  @override
  Future<void> deleteCompany(String companyId) async {
    await _lag();
    _companies.removeWhere((c) => c.id == companyId);
  }

  @override
  Future<void> resetCompanyData() async {
    await _lag();
    if (_self.role != Role.keeper) throw const AppException('ONLY_KEEPER');
    _products.clear();
    _customers.clear();
    _suppliers.clear();
    _batches.clear();
    _supplierPayments.clear();
    _receipts.clear();
    _soldLines.clear();
    _sessions.clear();
    _stock.clear();
  }

  // ═══════════════════════════════════════════════ تقارير: ربح + كشف حركة صنف
  bool _inScope(String whId, String? filterWh) => filterWh == null || whId == filterWh;

  @override
  Future<ProfitReport> profitReport(DateTime from, DateTime to, {String? warehouseId}) async {
    await _lag();
    final me = _self;
    final wh = me.role == Role.keeper ? me.whId : warehouseId;
    bool inRange(DateTime d) => !d.isBefore(from) && !d.isAfter(DateTime(to.year, to.month, to.day, 23, 59, 59));
    final rows = _soldLines.where((x) => _inScope(x.whId, wh) && inRange(x.at)).toList();
    final revenue = rows.fold<double>(0, (a, x) => a + x.qty * x.price);
    final cost = rows.fold<double>(0, (a, x) => a + x.qty * x.cost);
    final byDay = <DateTime, (double, double)>{};
    final byProduct = <String, (double, double, double)>{};
    for (final x in rows) {
      final d = DateTime(x.at.year, x.at.month, x.at.day);
      final cur = byDay[d] ?? (0, 0);
      byDay[d] = (cur.$1 + x.qty * x.price, cur.$2 + x.qty * x.cost);
      final cp = byProduct[x.productId] ?? (0, 0, 0);
      byProduct[x.productId] = (cp.$1 + x.qty, cp.$2 + x.qty * x.price, cp.$3 + x.qty * x.cost);
    }
    final days = byDay.entries.map((e) => ProfitDay(e.key, e.value.$1, e.value.$2)).toList()..sort((a, b) => a.day.compareTo(b.day));
    final items = byProduct.entries.map((e) => ProfitItem(_product(e.key).name, e.value.$1, e.value.$2, e.value.$3)).toList()
      ..sort((a, b) => b.profit.compareTo(a.profit));
    return ProfitReport(from: from, to: to, revenue: revenue, cost: cost, days: days, items: items);
  }

  @override
  Future<ProductLedger> productLedger(String productId, DateTime from, DateTime to) async {
    await _lag();
    final me = _self;
    final wh = me.role == Role.keeper ? me.whId : null;
    final pr = _product(productId);
    bool inRange(DateTime d) => !d.isBefore(from) && !d.isAfter(DateTime(to.year, to.month, to.day, 23, 59, 59));

    final received = _receipts.where((x) => x.productId == productId && _inScope(x.whId, wh) && inRange(x.at));
    final sold = _soldLines.where((x) => x.productId == productId && _inScope(x.whId, wh) && inRange(x.at));
    var issued = 0.0, returned = 0.0;
    for (final s in _sessions.where((s) => _inScope(s.whId, wh))) {
      final c = s.items[productId];
      if (c == null || !inRange(s.startedAt)) continue;
      issued += c.issued;
      returned += c.returned;
    }
    final inStock = _stock.entries.where((e) => _inScope(e.key, wh)).fold<double>(0, (a, e) => a + (e.value[productId] ?? 0));

    final movements = <ProductMovement>[
      for (final r in received)
        ProductMovement(kind: 'receive', at: r.at, qty: r.qty, title: r.supplierId == null ? 'استلام' : _suppliers.where((s) => s.id == r.supplierId).firstOrNull?.name),
      for (final s in _sessions.where((s) => _inScope(s.whId, wh) && s.items[productId] != null && inRange(s.startedAt)))
        ProductMovement(kind: 'issue', at: s.startedAt, qty: -s.items[productId]!.issued, title: _person(s.repId).name),
      for (final x in sold) ProductMovement(kind: 'sale', at: x.at, qty: -x.qty, title: _cust(x.customerId).name, price: x.price, costPrice: x.cost),
    ]..sort((a, b) => b.at!.compareTo(a.at!));

    return ProductLedger(
      productId: pr.id,
      productName: pr.name,
      unit: pr.unit,
      price: pr.price,
      cost: pr.cost,
      from: from,
      to: to,
      inStock: inStock,
      received: received.fold<double>(0, (a, x) => a + x.qty),
      issued: issued,
      returned: returned,
      sold: sold.fold<double>(0, (a, x) => a + x.qty),
      movements: movements.take(300).toList(),
    );
  }
}

// ═══════════════════════════════════════════════ in-memory rows
class _Company {
  final String id, code, name, manager;
  bool active;
  DateTime expiresAt;
  final int maxWh;
  final int? whCount;
  int reps, devices, devicesTotal, maxReps;
  List<_Person>? people;
  _Company(this.id, this.code, this.name, this.manager, this.active, this.expiresAt, this.maxWh,
      {this.reps = 0, this.devices = 0, this.devicesTotal = 0, this.maxReps = 0, this.whCount});
}

class _Wh {
  final String id, name, address;
  final double lat, lng;
  int maxReps;
  _Wh(this.id, this.name, this.address, this.lat, this.lng, this.maxReps);
}

class _Person {
  final String id;
  String name;
  final Role role;
  final String? whId;
  String key;
  String? device, serial, fingerprint, phone;
  DateTime? activatedAt, lastSeen;
  bool active = true;
  double? lat, lng;
  double speed = 0;
  _Person(this.id, this.name, this.role, this.whId, this.key, this.device, {String? companyId}) {
    if (device != null) {
      fingerprint = null; // بيتربط أول ما حد يفعّل بالمفتاح
      serial = 'SN-${id.hashCode.abs().toRadixString(16).toUpperCase()}';
      activatedAt = DateTime.now().subtract(const Duration(days: 30));
    }
  }
}

class _Product {
  final String id;
  String code, name, unit;
  double price;
  double? cost, cartonPrice;
  String? cartonUnit;
  double unitsPerCarton;
  bool active = true;
  _Product(this.id, this.code, this.name, this.unit, this.price, {this.cost, this.cartonUnit, this.unitsPerCarton = 1, this.cartonPrice});
}

class _Cust {
  final String id, whId, code, name, area;
  double balance, limit;
  _Cust(this.id, this.whId, this.code, this.name, this.area, this.balance, this.limit);
}

class _Supplier {
  final String id;
  String name;
  String? phone, address;
  double balance = 0;
  _Supplier(this.id, this.name, {this.phone, this.address});
}

class _SupplierPayment {
  final String id, no, supplierId;
  final double amount;
  final DateTime at;
  _SupplierPayment(this.id, this.no, this.supplierId, this.amount, this.at);
}

class _Batch {
  final String id, whId, productId;
  String? supplierId;
  DateTime? productionDate, expiryDate;
  double costPrice;
  double qty;
  final DateTime createdAt;
  _Batch(this.id, this.whId, this.productId, this.qty, this.createdAt,
      {this.supplierId, this.productionDate, this.expiryDate, this.costPrice = 0});
}

/// حركة استلام فعلية (وقت التشغيل) — لكشف حركة الصنف وتقرير الأرباح في وضع العرض.
class _Receipt {
  final String whId, productId;
  final String? supplierId;
  final double qty, costPrice;
  final DateTime at;
  _Receipt(this.whId, this.productId, this.supplierId, this.qty, this.costPrice, this.at);
}

/// سطر بيع فعلي (وقت التشغيل) بسعر وتكلفة — لتقرير الأرباح وكشف حركة الصنف.
class _SoldLine {
  final String whId, productId, customerId;
  final double qty, price, cost;
  final DateTime at;
  _SoldLine(this.whId, this.productId, this.customerId, this.qty, this.price, this.cost, this.at);
}

class _Custody {
  final String productId;
  final double price, issued;
  double costPrice;
  double sold = 0, returned = 0;
  _Custody(this.productId, this.price, this.issued, {this.costPrice = 0});
}

class _Sale {
  final String no, customerId;
  final DateTime at;
  final Map<String, double> lines;
  final double total;
  double paid, credit;
  bool voided = false;
  String? clientUuid;
  _Sale(this.no, this.customerId, this.at, this.lines, this.total, this.paid, this.credit);
}

class _Coll {
  final String no, customerId, clientUuid;
  final DateTime at;
  final double amount;
  _Coll(this.no, this.customerId, this.at, this.amount, this.clientUuid);
}

class _Session {
  final String id, repId, whId, issueNo;
  final DateTime startedAt;
  String status = 'open';
  DateTime? submittedAt;
  final items = <String, _Custody>{};
  final sales = <_Sale>[];
  final collections = <_Coll>[];
  Settlement? settlement;
  _Session(this.id, this.repId, this.whId, this.issueNo, this.startedAt);
}

class _Day {
  final DateTime day;
  final double sales, cash, credit, deficit;
  final Map<String, double> items;
  final int invoices;
  _Day(this.day, this.sales, this.cash, this.credit, this.deficit, this.items, this.invoices);
}
