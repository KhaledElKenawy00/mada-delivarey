import 'dart:io';

import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/device_identity.dart';
import 'models.dart';
import 'repository.dart';

class SupabaseRepository implements MadarRepository {
  SupabaseClient get _db => Supabase.instance.client;
  Profile? _me;
  String? _sessionId;

  static final _code = RegExp(r'^[A-Z_]+$');
  static final _ymd = DateFormat('yyyy-MM-dd');

  AppException _fromRaw(String raw) {
    final idx = raw.indexOf(':');
    if (idx > 0 && _code.hasMatch(raw.substring(0, idx))) {
      return AppException(raw.substring(0, idx), raw.substring(idx + 1).trim());
    }
    if (_code.hasMatch(raw)) return AppException(raw);
    return AppException('ERROR', raw);
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on AppException {
      rethrow;
    } on PostgrestException catch (e) {
      throw _fromRaw(e.message);
    } on FunctionException catch (e) {
      final det = e.details;
      throw _fromRaw(det is Map ? '${det['error']}' : '$det');
    } on AuthRetryableFetchException {
      throw const AppException('NETWORK');
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('invalid login')) throw const AppException('OTHER_DEVICE');
      throw AppException('AUTH', e.message);
    } on SocketException {
      throw const AppException('NETWORK');
    } catch (e) {
      final m = '$e';
      if (m.contains('SocketException') || m.contains('ClientException') || m.contains('Failed host lookup')) {
        throw const AppException('NETWORK');
      }
      rethrow;
    }
  }

  Future<dynamic> _rpc(String fn, [Map<String, dynamic>? params]) => _guard(() => _db.rpc(fn, params: params));

  Map<String, dynamic> _map(dynamic v) => Map<String, dynamic>.from(v as Map);

  Profile get _profile => _me ?? (throw const AppException('NO_PROFILE'));

  // ───────────────────────── الترخيص
  @override
  Future<Activation> activate(String key, DeviceIdentity device) => _guard(() async {
        final res = await _db.functions.invoke('activate-license', body: {
          'key': key,
          'fingerprint': device.fingerprint,
          'serial': device.serial,
          'device_name': device.deviceName,
          'platform': device.platform,
        });
        final data = _map(res.data);
        final creds = {'email': '${data['email']}', 'password': '${data['password']}'};
        await _db.auth.signOut();
        final profile = await restore(creds, device);
        return Activation(profile, creds);
      });

  @override
  Future<Profile> restore(Map<String, String> credentials, DeviceIdentity device) => _guard(() async {
        final email = credentials['email'];
        if (_db.auth.currentUser?.email != email) {
          await _db.auth.signInWithPassword(email: email!, password: credentials['password']!);
        }
        return verify(device);
      });

  @override
  Future<Profile> verify(DeviceIdentity device) async {
    final res = _map(await _rpc('check_license', {'p_fingerprint': device.fingerprint}));
    if (res['ok'] != true) throw AppException('${res['reason']}');
    _me = Profile.fromJson(_map(res['profile']));
    return _me!;
  }

  // ───────────────────────── أمين المخزن + المدير
  @override
  Future<WarehouseLive> warehouseLive([String? warehouseId]) async =>
      WarehouseLive.fromJson(_map(await _rpc('warehouse_live', {'p_wh': warehouseId})));

  @override
  Future<String> createStockIssue(String repId, List<IssueLine> lines) async {
    final r = _map(await _rpc('create_stock_issue', {
      'p_rep': repId,
      'p_items': lines.map((l) => l.toJson()).toList(),
    }));
    return '${r['no']}';
  }

  @override
  Future<SessionData> sessionData(String sessionId) async =>
      SessionData.fromJson(_map(await _rpc('settlement_data', {'p_session': sessionId})));

  @override
  Future<SessionData> approveSettlement(String sessionId, Map<String, double> returns, double receivedCash) async =>
      SessionData.fromJson(_map(await _rpc('approve_settlement', {
        'p_session': sessionId,
        'p_returns': [
          for (final e in returns.entries) {'product_id': e.key, 'qty': e.value}
        ],
        'p_received': receivedCash,
      })));

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
  }) =>
      _guard(() async {
        final row = {
          'code': code,
          'name': name,
          'unit': unit,
          'price': price,
          'cost': cost,
          'carton_unit': (cartonUnit ?? '').isEmpty ? null : cartonUnit,
          'units_per_carton': unitsPerCarton <= 0 ? 1 : unitsPerCarton,
          'carton_price': cartonPrice,
        };
        if (id == null) {
          final created = await _db.from('products').insert({...row, 'company_id': _profile.companyId}).select('id').single();
          if (openingQty != null && openingQty > 0) {
            await receiveStock([ReceiveLine(productId: created['id'] as String, qty: openingQty, costPrice: cost)]);
          }
        } else {
          await _db.from('products').update(row).eq('id', id);
        }
      });

  @override
  Future<ReceiveResult> receiveStock(List<ReceiveLine> lines, {String? supplierId, double? paid}) async =>
      ReceiveResult.fromJson(_map(await _rpc('receive_stock', {
        'p_items': [
          for (final l in lines)
            if (l.qty > 0) l.toJson()
        ],
        'p_supplier': supplierId,
        'p_paid': paid,
      })));

  @override
  Future<List<Customer>> customers() => _guard(() async {
        final rows = await _db.from('customers').select().order('name');
        return rows.map((r) => Customer.fromJson(r)).toList();
      });

  @override
  Future<List<Supplier>> suppliers() => _guard(() async {
        final rows = await _db.from('suppliers').select().order('name');
        return rows.map((r) => Supplier.fromJson(r)).toList();
      });

  @override
  Future<void> upsertSupplier({String? id, required String name, String? phone, String? address, double openingBalance = 0}) =>
      _guard(() async {
        final row = {'name': name, 'phone': phone, 'address': address};
        if (id == null) {
          await _db.from('suppliers').insert({...row, 'company_id': _profile.companyId, 'balance': openingBalance});
        } else {
          await _db.from('suppliers').update(row).eq('id', id);
        }
      });

  @override
  Future<List<SupplierPayment>> supplierPayments(String supplierId) => _guard(() async {
        final rows = await _db.from('supplier_payments').select().eq('supplier_id', supplierId).order('created_at', ascending: false);
        return rows.map((r) => SupplierPayment.fromJson(r)).toList();
      });

  @override
  Future<void> createSupplierPayment(String clientUuid, String supplierId, double amount) => _rpc('create_supplier_payment', {
        'p_client_uuid': clientUuid,
        'p_supplier': supplierId,
        'p_amount': amount,
      });

  @override
  Future<ProfitReport> profitReport(DateTime from, DateTime to, {String? warehouseId}) async =>
      ProfitReport.fromJson(_map(await _rpc('profit_report', {
        'p_from': _ymd.format(from),
        'p_to': _ymd.format(to),
        'p_warehouse': warehouseId,
      })));

  @override
  Future<ProductLedger> productLedger(String productId, DateTime from, DateTime to) async =>
      ProductLedger.fromJson(_map(await _rpc('product_movements', {
        'p_product': productId,
        'p_from': _ymd.format(from),
        'p_to': _ymd.format(to),
      })));

  @override
  Future<void> addCustomer({
    required String name,
    String? phone,
    String? area,
    String? code,
    double creditLimit = 0,
    double openingBalance = 0,
  }) =>
      _guard(() async {
        final p = _profile;
        await _db.from('customers').insert({
          'company_id': p.companyId,
          'warehouse_id': p.warehouseId,
          'rep_id': p.role == Role.rep ? p.id : null,
          'name': name,
          'phone': phone,
          'area': area,
          'code': code,
          'credit_limit': creditLimit,
          'balance': openingBalance,
        });
      });

  @override
  Future<ImportResult> importProducts(List<ProductImport> rows) async {
    final r = _map(await _rpc('import_products', {
      'p_rows': [
        for (final p in rows)
          {'code': p.code, 'name': p.name, 'unit': p.unit, 'price': p.price, 'cost': p.cost, 'opening_qty': p.openingQty}
      ],
    }));
    return ImportResult(inserted: i(r['inserted']), updated: i(r['updated']), skipped: i(r['skipped']));
  }

  @override
  Future<ImportResult> importCustomers(List<CustomerImport> rows) async {
    final r = _map(await _rpc('import_customers', {
      'p_rows': [
        for (final c in rows)
          {
            'code': c.code,
            'name': c.name,
            'phone': c.phone,
            'area': c.area,
            'address': c.address,
            'credit_limit': c.creditLimit,
            'opening_balance': c.openingBalance,
          }
      ],
    }));
    return ImportResult(inserted: i(r['inserted']), updated: i(r['updated']), skipped: i(r['skipped']));
  }

  // ───────────────────────── المندوب
  @override
  Future<SessionData?> myCustody() async {
    final r = await _rpc('my_custody');
    if (r == null) {
      _sessionId = null;
      return null;
    }
    final s = SessionData.fromJson(_map(r));
    _sessionId = s.sessionId;
    return s;
  }

  @override
  Future<SaleResult> createSale(String clientUuid, String customerId, List<SaleLine> lines, double paid) async {
    final r = _map(await _rpc('create_sale', {
      'p_client_uuid': clientUuid,
      'p_customer': customerId,
      'p_items': lines.map((l) => l.toJson()).toList(),
      'p_paid': paid,
    }));
    return SaleResult(no: '${r['no']}', total: d(r['total']), paid: d(r['paid']), credit: d(r['credit']));
  }

  @override
  Future<void> createCollection(String clientUuid, String customerId, double amount) =>
      _rpc('create_collection', {'p_client_uuid': clientUuid, 'p_customer': customerId, 'p_amount': amount});

  @override
  Future<void> submitDayEnd() => _rpc('submit_day_end');

  @override
  Future<void> pushLocation(double lat, double lng, double? accuracy, double? speed) => _guard(() async {
        final p = _profile;
        await _db.from('gps_locations').insert({
          'company_id': p.companyId,
          'rep_id': p.id,
          'session_id': _sessionId,
          'lat': lat,
          'lng': lng,
          'accuracy': accuracy,
          'speed': speed,
        });
      });

  // ───────────────────────── المدير
  @override
  Future<CompanyOverview> companyOverview() async => CompanyOverview.fromJson(_map(await _rpc('company_overview')));

  @override
  Future<RepReport> repReport(String repId, DateTime from, DateTime to) async => RepReport.fromJson(_map(await _rpc(
        'rep_report',
        {'p_rep': repId, 'p_from': _ymd.format(from), 'p_to': _ymd.format(to)},
      )));

  // ───────────────────────── السوبر أدمن
  @override
  Future<List<CompanyRow>> companies() async => list(await _rpc('admin_companies')).map(CompanyRow.fromJson).toList();

  @override
  Future<void> setCompanyActive(String companyId, bool active) =>
      _rpc('admin_set_company_active', {'p_company': companyId, 'p_active': active});

  @override
  Future<DateTime> extendCompany(String companyId, DurationUnit unit, int count) async {
    final interval = switch (unit) {
      DurationUnit.hour => '$count hours',
      DurationUnit.day => '$count days',
      DurationUnit.week => '${count * 7} days',
      DurationUnit.month => '$count months',
      DurationUnit.year => '$count years',
    };
    final r = await _rpc('admin_extend_company', {'p_company': companyId, 'p_interval': interval});
    return t(r) ?? DateTime.now();
  }

  @override
  Future<CompanyLicenses> companyLicenses(String companyId) async =>
      CompanyLicenses.fromJson(_map(await _rpc('admin_company_licenses', {'p_company': companyId})));

  @override
  Future<void> setLicenseActive(String licenseId, bool active) =>
      _rpc('admin_set_license_active', {'p_license': licenseId, 'p_active': active});

  @override
  Future<void> unbindLicense(String licenseId) => _rpc('admin_unbind_license', {'p_license': licenseId});

  @override
  Future<String> regenerateKey(String licenseId) async => '${await _rpc('admin_regenerate_key', {'p_license': licenseId})}';

  @override
  Future<List<CreatedAccount>> createCompany(NewCompanyInput input) => _guard(() async {
        final res = await _db.functions.invoke('admin', body: {
          'action': 'create_company',
          'name': input.name,
          'manager_name': input.managerName,
          'manager_phone': input.managerPhone,
          'warehouses': [
            for (final w in input.warehouses) {'name': w.name, 'reps': w.reps}
          ],
          'duration': {'unit': input.unit.name, 'count': input.count},
        });
        return list(_map(res.data)['accounts'])
            .map((a) => CreatedAccount(
                  role: roleFrom('${a['role']}'),
                  name: '${a['name']}',
                  key: '${a['key']}',
                  warehouse: s(a['warehouse']),
                ))
            .toList();
      });

  @override
  Future<CreatedAccount> addAccount({required String companyId, String? warehouseId, required Role role, required String name}) =>
      _guard(() async {
        final res = await _db.functions.invoke('admin', body: {
          'action': 'add_account',
          'company_id': companyId,
          'warehouse_id': warehouseId,
          'role': role == Role.keeper ? 'keeper' : (role == Role.manager ? 'manager' : 'rep'),
          'name': name,
        });
        final a = _map(res.data);
        return CreatedAccount(role: role, name: '${a['name']}', key: '${a['key']}');
      });

  @override
  Future<void> renameAccount(String profileId, String name, {String? phone}) =>
      _rpc('admin_update_profile', {'p_profile': profileId, 'p_name': name, 'p_phone': phone});

  @override
  Future<void> deleteCompany(String companyId) => _guard(() async {
        await _db.functions.invoke('admin', body: {'action': 'delete_company', 'company_id': companyId});
      });

  @override
  Future<void> resetCompanyData() => _rpc('keeper_reset_data');
}
