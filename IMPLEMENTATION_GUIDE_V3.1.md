# GARASI ABAH BONTOT V3.1
## Developer Implementation Guide

---

## 🎯 Objectives

V3.1 is a transaction logic patch focused on:

1. **Universal Transfer Admin Fee** - Finalize transfer fee structure for all expense transactions
2. **Income Destination Selection** - Support split amounts (CASH/BANK/CAMPURAN) for all income
3. **Edit Transaction Date** - Allow date editing for all transaction types
4. **Comprehensive Audit Logging** - Track all changes including date edits and fee changes

All changes maintain backward compatibility and support safe in-place updates.

---

## 📦 Implementation Structure

### Files Modified

#### Core Layer
- `pubspec.yaml` - Version bump: 1.0.0+1 → 1.0.1+2
- `lib/core/constants/app_constants.dart` - DB version 9 → 10, new constants
- `lib/core/database/database_helper.dart` - Migration v9 → v10, schema updates

#### Models
- `lib/models/pemasukan_model.dart` - Add split amounts + updated_at
- `lib/models/pengeluaran_model.dart` - Add updated_at for tracking

#### Repositories
- `lib/repositories/pemasukan_repository.dart` - Handle CAMPURAN split logic
- `lib/repositories/pengeluaran_repository.dart` - Finalize transfer fee logic
- `lib/repositories/audit_log_repository.dart` - Enhance logging for date changes

#### UI (To be implemented)
- `lib/screens/pengeluaran/pengeluaran_screen.dart` - Transfer type selection UI
- `lib/screens/pemasukan/pemasukan_screen.dart` - Income destination UI
- All transaction edit screens - Add date picker for date editing

#### Services
- `lib/services/laporan_service.dart` - Ensure split amounts properly calculated
- `lib/services/dashboard_service.dart` - Account for new fee structure

---

## 🗄️ Database Migration (v9 → v10)

### Migration Strategy
- **Additive only**: No data deletion or destructive changes
- **Default values**: All new columns have sensible defaults
- **Backward compatibility**: v3 code can still read v10 database structure

### Migration SQL

```sql
-- Add split amount columns to pemasukan
ALTER TABLE pemasukan ADD COLUMN cash_masuk REAL NOT NULL DEFAULT 0;
ALTER TABLE pemasukan ADD COLUMN bank_masuk REAL NOT NULL DEFAULT 0;
ALTER TABLE pemasukan ADD COLUMN updated_at TEXT;

-- Add tracking column to pengeluaran
ALTER TABLE pengeluaran ADD COLUMN updated_at TEXT;

-- Populate historical data
UPDATE pemasukan 
SET cash_masuk = CASE WHEN sumber = 'CASH' THEN nominal ELSE 0 END,
    bank_masuk = CASE WHEN sumber = 'BANK' THEN nominal ELSE 0 END,
    updated_at = created_at
WHERE cash_masuk = 0 AND bank_masuk = 0;

UPDATE pengeluaran 
SET jenis_transfer = 'GRATIS' 
WHERE jenis_transfer IS NULL AND sumber = 'BANK';

UPDATE pengeluaran 
SET biaya_admin = CASE 
  WHEN jenis_transfer = 'BI_FAST' THEN 2500
  WHEN jenis_transfer = 'REALTIME' THEN 6500
  ELSE 0
END,
updated_at = created_at
WHERE sumber = 'BANK' AND biaya_admin = 0;
```

### Migration Code Location
`lib/core/database/database_helper.dart` - Line 647+ in `_onUpgrade()` method

---

## 📱 Models Implementation

### PemasukanModel Changes

**New Fields:**
```dart
final double cashMasuk;      // Amount going to cash (for CAMPURAN)
final double bankMasuk;      // Amount going to bank (for CAMPURAN)
final DateTime updatedAt;    // Track last edit time
```

**Backward Compatibility:**
- Old pemasukan records have `cashMasuk` and `bankMasuk` auto-populated
- `updatedAt` defaults to `createdAt` for old records
- Query code continues to work unchanged

### PengeluaranModel Changes

**Updated Fields:**
```dart
final String? jenisTransfer;  // FINALIZED: GRATIS | BI_FAST | REALTIME
final double biayaAdmin;      // AUTO-CALCULATED from jenisTransfer
final DateTime updatedAt;     // Track last edit time
```

**Calculation:**
```dart
double get adminFeeForTransfer => biayaAdmin; // Already calculated
double get totalKeluar => nominal + biayaAdmin; // Total expense
```

---

## 🔄 Repository Implementation

### PemasukanRepository

#### Feature: CAMPURAN Support

```dart
Future<PemasukanModel> tambahPemasukan({
  required DateTime tanggal,
  required String kategori,
  required double nominal,
  String? keterangan,
  String sumber = AppConstants.sumberCash,  // CASH | BANK | CAMPURAN
  double cashMasuk = 0,  // NEW: for CAMPURAN split
  double bankMasuk = 0,  // NEW: for CAMPURAN split
  int? periodeId,
}) async {
  // Implementation must:
  // 1. Validate: if CAMPURAN, (cashMasuk + bankMasuk) == nominal
  // 2. Create proper PemasukanModel with split amounts
  // 3. Update cash saldo if cashMasuk > 0
  // 4. Update bank saldo if bankMasuk > 0
  // 5. Create two cash_flow entries (one per sumber)
  // 6. Audit log the transaction
  // 7. Handle "Tambah Modal" category (always CASH)
}
```

#### Feature: Edit with Date Change

```dart
Future<PemasukanModel> editPemasukan({
  required int id,
  required DateTime tanggal,  // NEW: allow date edit
  required String kategori,
  required double nominal,
  String? keterangan,
  String sumber = AppConstants.sumberCash,
  double cashMasuk = 0,
  double bankMasuk = 0,
}) async {
  // Implementation must:
  // 1. Load old pemasukan record
  // 2. Rollback old cash flows
  // 3. Update tanggal in database (ALLOWED)
  // 4. Create new cash flows with new date
  // 5. Audit log BOTH amount changes and date changes
  // 6. Maintain period consistency
}
```

### PengeluaranRepository

#### Feature: Universal Transfer Fee

```dart
Future<PengeluaranModel> tambahPengeluaran({
  required DateTime tanggal,
  required String kategori,
  required double nominal,
  String? keterangan,
  String sumber = AppConstants.sumberCash,
  String? jenisTransfer,  // GRATIS | BI_FAST | REALTIME
  int? periodeId,
}) async {
  // Implementation must:
  // 1. If sumber == BANK and jenisTransfer is null -> set to GRATIS
  // 2. Calculate biaya_admin from jenisTransfer:
  //    - GRATIS: 0
  //    - BI_FAST: 2500
  //    - REALTIME: 6500
  // 3. Total keluar = nominal + biaya_admin
  // 4. Deduct saldo by total_keluar amount
  // 5. Create cash flow entry with total amount
  // 6. Audit log includes fee information
}
```

#### Feature: Edit with Date & Fee Changes

```dart
Future<PengeluaranModel> editPengeluaran({
  required int id,
  required DateTime tanggal,  // NEW: allow date edit
  required String kategori,
  required double nominal,
  String? keterangan,
  String sumber = AppConstants.sumberCash,
  String? jenisTransfer,
}) async {
  // Implementation must:
  // 1. Load old pengeluaran record
  // 2. Rollback old cash flow (by old total amount)
  // 3. Calculate new biaya_admin if jenisTransfer changed
  // 4. Create new cash flow with updated date
  // 5. Audit log all changes:
  //    a. Date change: "Mengubah tanggal dari X ke Y"
  //    b. Fee change: "Mengubah jenis transfer dari X ke Y"
  // 6. Maintain period consistency
}
```

---

## 📝 Audit Logging Enhancement

### Log Entry Format for Date Changes

```
Tabel: pemasukan | pengeluaran | [other trans tables]
Record ID: [id]
Aksi: UPDATE
Keterangan: "Mengubah tanggal dari [old_date] menjadi [new_date]"
Data Lama: {"tanggal": "2026-08-10", ...}
Data Baru: {"tanggal": "2026-08-15", ...}
```

### Log Entry Format for Fee Changes

```
Tabel: pengeluaran
Record ID: [id]
Aksi: UPDATE
Keterangan: "Mengubah jenis transfer dari [old] menjadi [new] (biaya: Rp[amount])"
Data Lama: {"jenis_transfer": "GRATIS", "biaya_admin": 0}
Data Baru: {"jenis_transfer": "BI_FAST", "biaya_admin": 2500}
```

---

## 💰 Calculation Rules

### Transfer Fee Auto-Calculation

```dart
double calculateAdminFee(String jenisTransfer) {
  switch (jenisTransfer) {
    case AppConstants.jenisTransferGratis:
      return AppConstants.adminTransferGratis; // 0
    case AppConstants.jenisTransferBiFast:
      return AppConstants.adminTransferBiFast; // 2500
    case AppConstants.jenisTransferRealtime:
      return AppConstants.adminTransferRealtime; // 6500
    default:
      return 0;
  }
}
```

### Income Split Validation

```dart
bool validatePemasukanSplit(
  String sumber,
  double nominal,
  double cashMasuk,
  double bankMasuk,
) {
  if (sumber == AppConstants.sumberCampuran) {
    // CAMPURAN: must have split
    return (cashMasuk + bankMasuk) == nominal && 
           cashMasuk > 0 && 
           bankMasuk > 0;
  } else if (sumber == AppConstants.sumberCash) {
    // CASH: all to cash
    return cashMasuk == nominal && bankMasuk == 0;
  } else if (sumber == AppConstants.sumberBank) {
    // BANK: all to bank
    return cashMasuk == 0 && bankMasuk == nominal;
  }
  return false;
}
```

---

## 🧪 Testing Requirements

### Unit Tests

```dart
// Test transfer fee calculation
test('Transfer fee GRATIS should be 0', () {
  final fee = calculateAdminFee(AppConstants.jenisTransferGratis);
  expect(fee, 0);
});

test('Transfer fee BI_FAST should be 2500', () {
  final fee = calculateAdminFee(AppConstants.jenisTransferBiFast);
  expect(fee, 2500);
});

// Test CAMPURAN validation
test('CAMPURAN with valid split should pass', () {
  final valid = validatePemasukanSplit(
    AppConstants.sumberCampuran,
    10000000,
    3000000,
    7000000,
  );
  expect(valid, true);
});

test('CAMPURAN with invalid split should fail', () {
  final invalid = validatePemasukanSplit(
    AppConstants.sumberCampuran,
    10000000,
    3000000,
    6000000,  // Wrong: 3 + 6 = 9, not 10
  );
  expect(invalid, false);
});
```

### Integration Tests

```dart
// Test safe update: v9 → v10
test('Database migration v9 to v10 preserves data', () async {
  // 1. Create v9 database with test data
  // 2. Trigger migration to v10
  // 3. Verify all data exists in new schema
  // 4. Verify split amounts are correctly populated
});

// Test transfer fee persistence
test('Transfer fee applies and persists correctly', () async {
  // 1. Create pengeluaran with transfer fee
  // 2. Verify biaya_admin calculated correctly
  // 3. Verify saldo deducted by total amount
  // 4. Verify cash flow entry created
  // 5. Query and verify data matches
});

// Test CAMPURAN income split
test('CAMPURAN income splits correctly between cash and bank', () async {
  // 1. Create pemasukan with CAMPURAN split
  // 2. Verify cash saldo increased by cashMasuk
  // 3. Verify bank saldo increased by bankMasuk
  // 4. Verify total = cashMasuk + bankMasuk
  // 5. Verify two cash_flow entries created
});

// Test date edit and audit logging
test('Date edit is recorded in audit log', () async {
  // 1. Create pemasukan
  // 2. Edit tanggal
  // 3. Query audit log
  // 4. Verify audit entry shows old date → new date
  // 5. Verify reports recalculated with new date
});
```

---

## 🚀 Build & Deployment

### Pre-Build Checklist
- [ ] All models updated with new fields
- [ ] All repositories updated with new logic
- [ ] Database migration implemented correctly
- [ ] All tests pass: `flutter test`
- [ ] Code analysis passes: `flutter analyze`
- [ ] No breaking changes in public APIs

### Build Commands
```bash
# Clean build
flutter clean

# Get dependencies
flutter pub get

# Run analysis
flutter analyze

# Run tests
flutter test

# Build APK
flutter build apk --release

# Build AAB (for Play Store)
flutter build appbundle --release
```

### Signing Configuration
```gradle
signingConfigs {
    release {
        keyAlias = 'garasi_abah_bontot'
        keyPassword = 'password'
        storeFile = file('path/to/keystore.jks')
        storePassword = 'password'
    }
}
```

### APK Naming Convention
```
GARASI_ABAH_BONTOT_V3.1_PATCH_FINAL.apk
```

---

## 🔍 Code Review Checklist

### Database Changes
- [ ] Migration is additive only (no DROP, DELETE, TRUNCATE)
- [ ] All new columns have reasonable defaults
- [ ] Historical data properly migrated
- [ ] No data loss possible

### Model Changes
- [ ] Equatable props includes all fields
- [ ] toMap() exports all fields including new ones
- [ ] fromMap() handles missing fields gracefully
- [ ] Backward compatibility maintained

### Repository Changes
- [ ] All cash flow entries created with correct sumber
- [ ] Saldo calculations account for split amounts
- [ ] Rollback logic handles all scenarios
- [ ] Audit logging comprehensive and accurate

### UI Changes (When Implemented)
- [ ] New UI fields only show when relevant
- [ ] Date picker available for all editable dates
- [ ] Transfer type dropdown shows correct options
- [ ] CAMPURAN input validation works
- [ ] Forms save correctly with new fields

### Audit Logging
- [ ] Every change logged with clear description
- [ ] Date changes tracked separately
- [ ] Fee changes tracked separately
- [ ] User attribution clear

---

## 📊 Data Integrity Verification

### Post-Migration Checks
```sql
-- Verify all pemasukan have split amounts populated
SELECT COUNT(*) as empty_split FROM pemasukan 
WHERE (cash_masuk = 0 AND bank_masuk = 0) 
AND (sumber IN ('CASH', 'BANK', 'CAMPURAN'));

-- Should return 0

-- Verify all pengeluaran have updated_at
SELECT COUNT(*) as missing_updated_at FROM pengeluaran 
WHERE updated_at IS NULL;

-- Should return 0

-- Verify fee consistency
SELECT COUNT(*) as invalid_fees FROM pengeluaran 
WHERE sumber = 'BANK' 
AND jenis_transfer IN ('BI_FAST', 'REALTIME')
AND biaya_admin = 0;

-- Should return 0
```

---

## 🎯 Performance Considerations

### Database Queries
- Migration should complete in <2 seconds (even with large dataset)
- Queries use indexed columns where possible
- No N+1 query problems in repositories

### UI Responsiveness
- Forms respond immediately to input
- No blocking operations on main thread
- Calculations happen in background where needed

---

## 🔐 Security Considerations

### Input Validation
- All currency amounts validated as positive numbers
- Date inputs validated for reasonable ranges
- Transaction categories validated against allowed list
- User permissions checked before allowing edits

### Audit Trail
- All changes logged with timestamp and user
- Audit log immutable (no delete/edit of logs)
- Sensitive operations flagged for review

---

## 📚 Documentation Requirements

- [ ] CHANGELOG_V3.1.md - User-facing changelog ✓
- [ ] SAFE_UPDATE_GUIDE_V3.1.md - Update instructions ✓
- [ ] IMPLEMENTATION_GUIDE_V3.1.md - This file ✓
- [ ] Inline code comments for complex logic
- [ ] README.md updated with V3.1 info

---

## ✅ Final Checklist

Before release:

- [ ] All code changes implemented
- [ ] All tests passing
- [ ] Code review completed
- [ ] Database migration tested
- [ ] Safe update verified
- [ ] Documentation complete
- [ ] APK built and signed
- [ ] Version numbers updated
- [ ] Android identity preserved
- [ ] GitHub workflow compatible

---

**Generated:** August 17, 2026  
**Version:** 1.0.1+2  
**Database:** v10

