class WarpHistoryRecord {
  final String id;
  final String recordTimestamp;
  final String eventDate;
  final String username;
  final String changeType;
  final double valueChange;
  final double newTotalWarp;
  final String remarks;

  const WarpHistoryRecord({
    required this.id,
    required this.recordTimestamp,
    required this.eventDate,
    required this.username,
    required this.changeType,
    required this.valueChange,
    required this.newTotalWarp,
    required this.remarks,
  });

  factory WarpHistoryRecord.fromJson(Map<String, dynamic> json) {
    return WarpHistoryRecord(
      id: (json['_id'] ?? '').toString(),
      recordTimestamp: (json['record_timestamp'] ?? '').toString(),
      eventDate: (json['event_date'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      changeType: (json['change_type'] ?? '').toString(),
      valueChange: (json['value_change'] is num) ? (json['value_change'] as num).toDouble() : double.tryParse('${json['value_change']}') ?? 0.0,
      newTotalWarp: (json['new_total_warp'] is num) ? (json['new_total_warp'] as num).toDouble() : double.tryParse('${json['new_total_warp']}') ?? 0.0,
      remarks: (json['remarks'] ?? '').toString(),
    );
  }
}
