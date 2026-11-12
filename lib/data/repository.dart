import '../core/device_identity.dart';
import 'models.dart';

/// خطأ من السيرفر بكود معروف (من الـ RPC أو الـ Edge Function)
class AppException implements Exception {
  final String code;
  final String? detail;
  const AppException(this.code, [this.detail]);

  String get message => switch (code) {
        'INVALID_KEY' => 'مفتاح الترخيص ده مش موجود',
        'ALREADY_BOUND' => 'المفتاح ده متفعّل على جهاز تاني. اطلب من الإدارة فك الربط.',
        'OTHER_DEVICE' => 'الترخيص اتنقل لجهاز تاني',
        'UNBOUND' => 'الإدارة فكت ربط الجهاز ده. فعّله تاني بالمفتاح.',
        'LICENSE_SUSPENDED' => 'الترخيص ده موقوف من الإدارة',
        'USER_SUSPENDED' => 'الحساب ده موقوف',
        'COMPANY_SUSPENDED' => 'حساب الشركة موقوف. تواصل مع الدعم.',
        'LICENSE_EXPIRED' => 'مدة تفعيل الشركة انتهت',
        'LICENSE_INACTIVE' => 'الترخيص مش مفعّل',
        'NO_PROFILE' || 'NO_LICENSE' => 'الحساب مش مكتمل. تواصل مع الإدارة.',
        'REP_HAS_OPEN_SESSION' => 'المندوب ده عنده عهدة مفتوحة لسه ماتسوّتش',
        'REP_NOT_IN_WAREHOUSE' => 'المندوب مش تابع لمخزنك',
        'INSUFFICIENT_STOCK' => 'رصيد المخزن مش كفاية${detail == null ? '' : ' — $detail'}',
        'EXCEEDS_CUSTODY' => 'الكمية أكبر من عهدتك${detail == null ? '' : ' — $detail'}',
        'NO_OPEN_SESSION' => 'مفيش يوم عمل مفتوح. استنى إذن الصرف من أمين المخزن.',
        'CREDIT_NOT_ALLOWED' => 'الشركة مش مسموح لها بالبيع الآجل',
        'BAD_RETURN_QTY' => 'كمية المرتجع غلط',
        'BAD_SUPPLIER' => 'المورد ده مش موجود',
        'EMPTY_RECEIPT' => 'لازم تضيف صنف واحد على الأقل',
        'BAD_AMOUNT' => 'المبلغ غلط',
        'ALREADY_CLOSED' => 'اليوم ده اتقفل قبل كده',
        'EMPTY_ISSUE' || 'EMPTY_SALE' => 'لازم تضيف صنف واحد على الأقل',
        'FORBIDDEN' || 'ONLY_KEEPER' || 'ONLY_REP' || 'ONLY_MANAGER' => 'مش مسموح لك بالعملية دي',
        'NETWORK' => 'مفيش اتصال بالإنترنت',
        _ => detail ?? code,
      };

  @override
  String toString() => message;
}

class Activation {
  final Profile profile;
  final Map<String, String> credentials;
  const Activation(this.profile, this.credentials);
}

/// كل اللي الشاشات محتاجاه من الباك إند.
/// ليها تنفيذين: SupabaseRepository (حقيقي) و DemoRepository (بيانات عرض في الذاكرة).
abstract class MadarRepository {
  // ── الترخيص
  Future<Activation> activate(String key, DeviceIdentity device);
  Future<Profile> restore(Map<String, String> credentials, DeviceIdentity device);
  Future<Profile> verify(DeviceIdentity device);

  // ── أمين المخزن + المدير
  Future<WarehouseLive> warehouseLive([String? warehouseId]);
  Future<String> createStockIssue(String repId, List<IssueLine> lines);
  Future<SessionData> sessionData(String sessionId);
  Future<SessionData> approveSettlement(String sessionId, Map<String, double> returns, double receivedCash);
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
  });
  Future<ReceiveResult> receiveStock(List<ReceiveLine> lines, {String? supplierId, double? paid});
  Future<List<Customer>> customers();
  Future<void> addCustomer({
    required String name,
    String? phone,
    String? area,
    String? code,
    double creditLimit = 0,
    double openingBalance = 0,
  });

  // ── الموردين (مشتركين على مستوى الشركة)
  Future<List<Supplier>> suppliers();
  Future<void> upsertSupplier({String? id, required String name, String? phone, String? address, double openingBalance = 0});
  Future<List<SupplierPayment>> supplierPayments(String supplierId);
  Future<void> createSupplierPayment(String clientUuid, String supplierId, double amount);

  // ── تقارير: ربح + كشف حركة صنف
  Future<ProfitReport> profitReport(DateTime from, DateTime to, {String? warehouseId});
  Future<ProductLedger> productLedger(String productId, DateTime from, DateTime to);

  /// استيراد من Excel — الكود موجود؟ يتحدث. جديد؟ يتضاف. (والكمية الافتتاحية بتدخل رصيد المخزن)
  Future<ImportResult> importProducts(List<ProductImport> rows);
  Future<ImportResult> importCustomers(List<CustomerImport> rows);

  // ── المندوب
  Future<SessionData?> myCustody();
  Future<SaleResult> createSale(String clientUuid, String customerId, List<SaleLine> lines, double paid);
  Future<void> createCollection(String clientUuid, String customerId, double amount);
  Future<void> submitDayEnd();
  Future<void> pushLocation(double lat, double lng, double? accuracy, double? speed);

  // ── المدير
  Future<CompanyOverview> companyOverview();
  Future<RepReport> repReport(String repId, DateTime from, DateTime to);

  // ── السوبر أدمن
  Future<List<CompanyRow>> companies();
  Future<void> setCompanyActive(String companyId, bool active);
  Future<DateTime> extendCompany(String companyId, DurationUnit unit, int count);
  Future<CompanyLicenses> companyLicenses(String companyId);
  Future<void> setLicenseActive(String licenseId, bool active);
  Future<void> unbindLicense(String licenseId);
  Future<String> regenerateKey(String licenseId);
  Future<List<CreatedAccount>> createCompany(NewCompanyInput input);
  Future<CreatedAccount> addAccount({required String companyId, String? warehouseId, required Role role, required String name});
  Future<void> renameAccount(String profileId, String name, {String? phone});
  Future<void> deleteCompany(String companyId);

  // ── أمين المخزن: مسح بيانات الشركة (أصناف + عملاء + فواتير)
  Future<void> resetCompanyData();
}
