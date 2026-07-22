// Datenmodelle für die Zeiterfassung – gemappt auf die Rückgaben von
// apex.workforce.mobile.* (get_me/get_status, get_lookups, get_positions).

class TimeStatus {
  final String employee;
  final String name;
  final bool clockedIn;
  final bool onBreak;
  final RunningEntry? running;
  final double todayHours;
  final bool requireCostCenter;
  final bool requireProjectOrder;
  final bool allowTeam;
  final List<TeamMember> team;
  final String? teamUntil;
  final String captureMode; // "Manual and QR Code" | "Manual" | "QR Code"
  final bool canBookOthers;
  final bool requireGps; // GPS beim Buchen zwingend (Default: ja)

  const TimeStatus({
    required this.employee,
    required this.name,
    required this.clockedIn,
    required this.onBreak,
    required this.running,
    required this.todayHours,
    required this.requireCostCenter,
    required this.requireProjectOrder,
    this.allowTeam = false,
    this.team = const [],
    this.teamUntil,
    this.captureMode = 'Manual and QR Code',
    this.canBookOthers = false,
    this.requireGps = true,
  });

  bool get canManual => captureMode.toLowerCase().contains('manual');
  bool get canScan => captureMode.toLowerCase().contains('qr');

  factory TimeStatus.fromJson(Map<String, dynamic> j) {
    final config = (j['config'] as Map?)?.cast<String, dynamic>() ?? const {};
    final running = j['running'];
    final teamData = (j['team'] as Map?)?.cast<String, dynamic>() ?? const {};
    return TimeStatus(
      employee: '${j['employee'] ?? ''}',
      name: '${j['name'] ?? j['employee'] ?? ''}',
      clockedIn: j['clocked_in'] == true,
      onBreak: j['on_break'] == true,
      running: (running is Map)
          ? RunningEntry.fromJson(running.cast<String, dynamic>())
          : null,
      todayHours: _toDouble(j['today_hours']),
      requireCostCenter: config['require_cost_center'] == true,
      requireProjectOrder: config['require_project_order'] == true,
      allowTeam: config['allow_team'] == true,
      team: ((teamData['members'] as List?) ?? [])
          .map((e) => TeamMember.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      teamUntil: teamData['until']?.toString(),
      captureMode: config['capture_mode']?.toString() ?? 'Manual and QR Code',
      canBookOthers: config['can_book_others'] == true,
      // Fehlt der Backend-Schalter, ist GPS Pflicht.
      requireGps: config.containsKey('use_gps') ? config['use_gps'] == true : true,
    );
  }

  bool get hasTeam => team.isNotEmpty;

  /// Zustand für die Anzeige.
  TimeState get state {
    if (!clockedIn) return TimeState.out;
    if (onBreak) return TimeState.paused;
    return TimeState.working;
  }
}

enum TimeState { out, working, paused }

class RunningEntry {
  final DateTime? since;
  final String? costCenter;
  final String? projectOrder;
  final String? position;
  // Lesbare Labels (v21 get_status):
  final String? customer;
  final String? projectOrderNo;
  final String? positionLabel;
  final String? costCenterLabel;

  const RunningEntry({
    required this.since,
    required this.costCenter,
    required this.projectOrder,
    required this.position,
    this.customer,
    this.projectOrderNo,
    this.positionLabel,
    this.costCenterLabel,
  });

  factory RunningEntry.fromJson(Map<String, dynamic> j) => RunningEntry(
        since: j['since'] != null ? DateTime.tryParse('${j['since']}') : null,
        costCenter: j['cost_center']?.toString(),
        projectOrder: j['project_order']?.toString(),
        position: j['project_order_position']?.toString(),
        customer: j['customer']?.toString(),
        projectOrderNo: j['project_order_no']?.toString(),
        positionLabel: j['position_label']?.toString(),
        costCenterLabel: j['cost_center_label']?.toString(),
      );

  // Bevorzugt die lesbaren Labels, fällt sonst auf die IDs zurück.
  String? get vorgangDisplay => projectOrderNo ?? projectOrder;
  String? get positionDisplay => positionLabel ?? position;
  String? get kostenstelleDisplay => costCenterLabel ?? costCenter;
}

class CostCenter {
  final String name;
  final String? number;
  final String? title;
  final String? groupLabel;

  const CostCenter({
    required this.name,
    this.number,
    this.title,
    this.groupLabel,
  });

  factory CostCenter.fromJson(Map<String, dynamic> j) => CostCenter(
        name: '${j['name']}',
        number: j['cost_center_no']?.toString(),
        title: j['name1']?.toString(),
        groupLabel: j['group_label']?.toString(),
      );

  String get label =>
      [if (number != null) number, if (title != null) title].join('  ');
}

class ProjectOrder {
  final String name;
  final String? fullNumber;
  final String? customer;
  final String? designation;
  final bool requirePositions;

  const ProjectOrder({
    required this.name,
    this.fullNumber,
    this.customer,
    this.designation,
    this.requirePositions = false,
  });

  factory ProjectOrder.fromJson(Map<String, dynamic> j) => ProjectOrder(
        name: '${j['name']}',
        fullNumber: j['full_number']?.toString(),
        customer: j['customer']?.toString(),
        designation: j['designation']?.toString(),
        requirePositions: j['require_time_tracking_positions'] == true,
      );

  String get label => fullNumber ?? name;
  String? get subtitle => [
        if (customer != null && customer!.isNotEmpty) customer,
        if (designation != null && designation!.isNotEmpty) designation,
      ].join(' · ').ifEmptyNull();
}

class Position {
  final String name;
  final String? positionNo;
  final String? designation;

  const Position({required this.name, this.positionNo, this.designation});

  factory Position.fromJson(Map<String, dynamic> j) => Position(
        name: '${j['name']}',
        positionNo: j['positionno']?.toString(),
        designation: j['designation']?.toString(),
      );

  String get label =>
      [if (positionNo != null) positionNo, if (designation != null) designation]
          .whereType<String>()
          .join('  ');
}

class Lookups {
  final List<CostCenter> costCenters;
  final List<ProjectOrder> projectOrders;

  const Lookups({required this.costCenters, required this.projectOrders});

  factory Lookups.fromJson(Map<String, dynamic> j) => Lookups(
        costCenters: ((j['cost_centers'] as List?) ?? [])
            .map((e) => CostCenter.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        projectOrders: ((j['project_orders'] as List?) ?? [])
            .map((e) => ProjectOrder.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

/// Ein Team-Mitglied (Kolonne) inkl. aktuellem Status – aus _emp_brief.
class TeamMember {
  final String employee;
  final String? employeeNumber;
  final String name;
  final bool clockedIn;
  final bool onBreak;
  final String? customer;
  final String? projectOrderNo;
  final String? positionLabel;
  final String? costCenterLabel;

  const TeamMember({
    required this.employee,
    required this.name,
    required this.clockedIn,
    required this.onBreak,
    this.employeeNumber,
    this.customer,
    this.projectOrderNo,
    this.positionLabel,
    this.costCenterLabel,
  });

  factory TeamMember.fromJson(Map<String, dynamic> j) => TeamMember(
        employee: '${j['employee']}',
        employeeNumber: j['employee_number']?.toString(),
        name: '${j['name'] ?? j['employee']}',
        clockedIn: j['clocked_in'] == true,
        onBreak: j['on_break'] == true,
        customer: j['customer']?.toString(),
        projectOrderNo: j['project_order_no']?.toString(),
        positionLabel: j['position_label']?.toString(),
        costCenterLabel: j['cost_center_label']?.toString(),
      );

  TimeState get state {
    if (!clockedIn) return TimeState.out;
    if (onBreak) return TimeState.paused;
    return TimeState.working;
  }

  /// Kurze Beschreibung der aktuellen Buchung fürs Kärtchen.
  String? get bookingSummary {
    final parts = [
      if (projectOrderNo != null && projectOrderNo!.isNotEmpty) projectOrderNo,
      if (customer != null && customer!.isNotEmpty) customer,
      if (costCenterLabel != null && costCenterLabel!.isNotEmpty) costCenterLabel,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0;
}

extension _EmptyNull on String {
  String? ifEmptyNull() => isEmpty ? null : this;
}
