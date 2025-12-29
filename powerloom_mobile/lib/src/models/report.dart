class ReportRecord {
  final String loomerName;
  final String loomNumber;
  final String shift;
  final int meters;
  final String salaryPerMeter;
  final String calculatedSalary;
  final String? dateFormatted;

  const ReportRecord({
    required this.loomerName,
    required this.loomNumber,
    required this.shift,
    required this.meters,
    required this.salaryPerMeter,
    required this.calculatedSalary,
    required this.dateFormatted,
  });

  factory ReportRecord.fromJson(Map<String, dynamic> json) {
    return ReportRecord(
      loomerName: (json['loomer_name'] ?? '').toString(),
      loomNumber: (json['loom_number'] ?? '').toString(),
      shift: (json['shift'] ?? '').toString(),
      meters: (json['meters'] ?? 0) is int ? (json['meters'] as int) : int.tryParse('${json['meters']}') ?? 0,
      salaryPerMeter: (json['salary_per_meter'] ?? '').toString(),
      calculatedSalary: (json['calculated_salary'] ?? '').toString(),
      dateFormatted: json['date_formatted']?.toString(),
    );
  }
}

class ReportSubtotal {
  final String key;
  final int totalMeters;
  final String totalSalary;

  const ReportSubtotal({
    required this.key,
    required this.totalMeters,
    required this.totalSalary,
  });

  factory ReportSubtotal.fromJson({required String keyField, required Map<String, dynamic> json}) {
    return ReportSubtotal(
      key: (json[keyField] ?? '').toString(),
      totalMeters: (json['total_meters'] ?? 0) is int ? (json['total_meters'] as int) : int.tryParse('${json['total_meters']}') ?? 0,
      totalSalary: (json['total_salary'] ?? '').toString(),
    );
  }
}

class ReportResult {
  final int totalMeters;
  final String totalSalary;
  final int recordCount;
  final List<ReportRecord> records;
  final List<ReportSubtotal> loomSubtotals;
  final List<ReportSubtotal> dailySubtotals;

  const ReportResult({
    required this.totalMeters,
    required this.totalSalary,
    required this.recordCount,
    required this.records,
    required this.loomSubtotals,
    required this.dailySubtotals,
  });

  factory ReportResult.fromJson(Map<String, dynamic> json) {
    final recordsJson = (json['records'] as List? ?? const []).cast<dynamic>();
    final loomJson = (json['loom_subtotals'] as List? ?? const []).cast<dynamic>();
    final dailyJson = (json['daily_subtotals'] as List? ?? const []).cast<dynamic>();

    return ReportResult(
      totalMeters: (json['total_meters'] ?? 0) is int ? (json['total_meters'] as int) : int.tryParse('${json['total_meters']}') ?? 0,
      totalSalary: (json['total_salary'] ?? '').toString(),
      recordCount: (json['record_count'] ?? 0) is int ? (json['record_count'] as int) : int.tryParse('${json['record_count']}') ?? 0,
      records: recordsJson
          .map((e) => ReportRecord.fromJson((e as Map).cast<String, dynamic>()))
          .toList(growable: false),
      loomSubtotals: loomJson
          .map((e) => ReportSubtotal.fromJson(keyField: 'loom_number', json: (e as Map).cast<String, dynamic>()))
          .toList(growable: false),
      dailySubtotals: dailyJson
          .map((e) => ReportSubtotal.fromJson(keyField: 'date', json: (e as Map).cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}
