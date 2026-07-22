import 'dart:convert';
import '../models/time_models.dart';
import 'frappe_client.dart';

/// Kapselt die Zeiterfassungs-Aufrufe an apex.workforce.mobile.*.
///
/// Alle buchenden Aktionen geben den neuen [TimeStatus] zurück. Mit [employee]
/// wird für ein Team-Mitglied gebucht, mit [applyTeam] für das ganze Team.
/// (Die Offline-Warteschlange wird später hier eingezogen.)
class TimeTrackingService {
  TimeTrackingService(this._client);
  final FrappeClient _client;

  static const _base = 'apex.workforce.mobile';

  Future<TimeStatus> getMe() async {
    final data = await _client.getMe();
    return TimeStatus.fromJson(data);
  }

  Future<Lookups> getLookups() async {
    final data = await _client.callMethod('$_base.get_lookups');
    return Lookups.fromJson((data as Map).cast<String, dynamic>());
  }

  /// Zuletzt verwendete Vorgänge/Kostenstellen (für „Zuletzt verwendet").
  Future<({List<ProjectOrder> projectOrders, List<CostCenter> costCenters})>
      getRecent() async {
    final data = await _client.callMethod('$_base.get_recent');
    final map = (data as Map).cast<String, dynamic>();
    return (
      projectOrders: ((map['project_orders'] as List?) ?? [])
          .map((e) => ProjectOrder.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      costCenters: ((map['cost_centers'] as List?) ?? [])
          .map((e) => CostCenter.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }

  Future<List<Position>> getPositions(String projectOrder) async {
    final data = await _client.callMethod(
      '$_base.get_positions',
      args: {'project_order': projectOrder},
    );
    return ((data as List?) ?? [])
        .map((e) => Position.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  // --- Team ------------------------------------------------------------------

  /// Auswählbare Team-Mitglieder (Pool) für den Team-Dialog.
  Future<List<TeamMember>> getTeamOptions() async {
    final data = await _client.callMethod('$_base.get_team_options');
    return ((data as List?) ?? [])
        .map((e) => TeamMember.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Speichert die Team-Auswahl (optional mit Gültigkeit bis [until] = YYYY-MM-DD).
  Future<void> setTeam(List<String> employees, {String? until}) async {
    await _client.callMethod(
      '$_base.set_team',
      args: {
        'employees': jsonEncode(employees),
        'until': ?until,
      },
      post: true,
    );
  }

  // --- Buchen / Aktionen -----------------------------------------------------

  /// Bucht die aktuelle Zuordnung (schließt eine offene Buchung, startet neu).
  Future<TimeStatus> book({
    String? costCenter,
    String? projectOrder,
    String? position,
    double? latitude,
    double? longitude,
    String? employee,
    bool applyTeam = false,
  }) async {
    final args = <String, dynamic>{
      'cost_center': ?costCenter,
      'project_order': ?projectOrder,
      'project_order_position': ?position,
      'latitude': ?latitude,
      'longitude': ?longitude,
      'employee': ?employee,
      if (applyTeam) 'apply_team': 1,
    };
    final data = await _client.callMethod('$_base.book', args: args, post: true);
    return TimeStatus.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<TimeStatus> clockOut({String? employee, bool applyTeam = false}) =>
      _action('clock_out', employee: employee, applyTeam: applyTeam);

  Future<TimeStatus> pause({String? employee, bool applyTeam = false}) =>
      _action('pause', employee: employee, applyTeam: applyTeam);

  Future<TimeStatus> resume({String? employee, bool applyTeam = false}) =>
      _action('resume', employee: employee, applyTeam: applyTeam);

  Future<TimeStatus> _action(
    String fn, {
    String? employee,
    bool applyTeam = false,
  }) async {
    final args = <String, dynamic>{
      'employee': ?employee,
      if (applyTeam) 'apply_team': 1,
    };
    final data = await _client.callMethod('$_base.$fn', args: args, post: true);
    return TimeStatus.fromJson((data as Map).cast<String, dynamic>());
  }
}
