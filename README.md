# Site Daily Log — Merged Build

Offline-first Flutter app for construction site engineers to track daily logs, expenses, materials, equipment, crew attendance, and cash float reconciliation.

## Features (Build A + Build B merged)

### Build A base
- Project → Site → DailyLog hierarchy with UUID keys
- SQLite with migrations (v1 → v2 → v3)
- PDF reports (site-level & project-level)
- Excel (.xlsx) export with 6 tabs
- Google Drive backup/restore (`appdata` scope)
- Photo compression before local save
- Provider-based sync badges
- Quick-add bottom sheets (long-press for full form)

### Build B additions
- **Crew Attendance** — Present / Absent / Half-Day per worker per daily log
- **Cash Float Reconciliation** — Opening + Float − Expenses = Expected vs Reported closing, variance detection, out-of-pocket deficit alerts
- **Material Stock Ledger** — Opening / Received / Issued / Closing per item per day
- **Equipment Dipping & Fuel** — Dip-stick readings (cm) + diesel/engine oil issued
- **Analytics Dashboard** — Bar chart (category spend), Pie chart (budget share), Line chart (daily burn rate), Dual line chart (cumulative float vs spend) via `fl_chart`
- **Daily Log Detail** — Read-only executive view with attendance, materials, equipment, expenses, one-tap PDF export
- **Daily Log List** — Dedicated scrollable list per site
- **GPS Photo Watermarking** — Site name, date/time, lat/lng stamped on photos (compress → watermark pipeline)
- **Naira Currency Formatter** — `₦` prefix with compact notation (₦1.2K, ₦3.5M)
- **Itemized Expense Ledger** — 10 locked categories, auto S/N per month, unit + unit price + total
- **Excel enhancements** — Monthly Summary, Overall Summary, Cash Flow tabs
- **PDF daily report** — Navy/steel-blue styled per-daily-log report with signature blocks

## Architecture

```
lib/
├── main.dart
├── db/
│   └── database_helper.dart          # SQLite + 6 new query methods
├── models/
│   ├── project.dart
│   ├── site.dart
│   ├── daily_log.dart
│   ├── expense.dart                  # 10-category enum + itemized fields
│   ├── material_item.dart
│   ├── worker.dart
│   ├── attendance.dart
│   ├── material_stock_log.dart
│   ├── equipment_dipping_log.dart
│   └── cash_float.dart
├── screens/
│   ├── project_list_screen.dart
│   ├── project_dashboard_screen.dart
│   ├── site_detail_screen.dart       # Dashboard: 4 summary cards + quick-actions + recent logs
│   ├── add_daily_log_screen.dart     # Compress → watermark pipeline
│   ├── add_expense_screen.dart       # 10 categories, S/N, unit, unit price
│   ├── attendance_screen.dart
│   ├── cash_float_screen.dart
│   ├── material_equipment_log_screen.dart
│   ├── analytics_screen.dart         # fl_chart dashboards
│   ├── daily_log_detail_screen.dart  # Read-only + PDF export
│   └── daily_log_list_screen.dart
├── services/
│   ├── pdf_report_service.dart       # Site, Project, DailyLog reports
│   ├── excel_export_service.dart     # 6-tab workbooks
│   ├── image_compression_service.dart
│   ├── photo_watermark_service.dart  # GPS + date/time stamp
│   └── google_drive_service.dart     # Backup/restore
├── utils/
│   └── currency_formatter.dart       # ₦ Naira formatting
└── widgets/
    ├── quick_expense_sheet.dart
    └── quick_log_sheet.dart          # Compress → watermark
```

## Dependencies added

```yaml
fl_chart: ^0.66.0      # Analytics dashboards
image: ^4.1.3          # Photo watermarking
```

## Getting Started

1. `flutter pub get`
2. `flutter run`
3. For release builds, configure `android/app/build.gradle` signing.

## License

MIT
