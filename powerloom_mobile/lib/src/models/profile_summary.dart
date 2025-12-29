class ProfileTotals {
  final String scope;
  final int totalRecords;
  final double totalMeters;
  final double totalSalary;

  const ProfileTotals({
    required this.scope,
    required this.totalRecords,
    required this.totalMeters,
    required this.totalSalary,
  });

  factory ProfileTotals.fromJson(Map<String, dynamic> json) {
    return ProfileTotals(
      scope: (json['scope'] ?? '').toString(),
      totalRecords: (json['total_records'] ?? 0) as int,
      totalMeters: (json['total_meters'] ?? 0).toDouble(),
      totalSalary: (json['total_salary'] ?? 0).toDouble(),
    );
  }
}

class ProfileUser {
  final String username;
  final String role;
  final String? createdAt;

  const ProfileUser({
    required this.username,
    required this.role,
    required this.createdAt,
  });

  factory ProfileUser.fromJson(Map<String, dynamic> json) {
    return ProfileUser(
      username: (json['username'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      createdAt: json['created_at']?.toString(),
    );
  }
}

class ProfileSummary {
  final ProfileUser user;
  final ProfileTotals totals;

  const ProfileSummary({
    required this.user,
    required this.totals,
  });

  factory ProfileSummary.fromJson(Map<String, dynamic> json) {
    return ProfileSummary(
      user: ProfileUser.fromJson((json['user'] as Map).cast<String, dynamic>()),
      totals: ProfileTotals.fromJson((json['totals'] as Map).cast<String, dynamic>()),
    );
  }
}
