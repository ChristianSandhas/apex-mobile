# Backend-Anpassung für Offline-Buchungen: `booked_at`

**Ziel:** Nachgereichte Offline-Buchungen bekommen die **echte** Arbeitszeit statt der Sync-Zeit.
Dazu müssen die Buchungsfunktionen einen optionalen ISO-Zeitstempel `booked_at` akzeptieren und
statt `now_datetime()` verwenden, wenn er mitgeliefert wird.

Umzusetzen im Frappe-Projekt `apex` (Modul `apex.workforce`). Betrifft `kiosk.py` und `mobile.py`.

---

## 1) `apex/workforce/kiosk.py`

### Helfer oben ergänzen
```python
def _stamp(booked_at: str | None):
    """Nutzt den mitgelieferten Zeitstempel (Offline-Nachbuchung) oder jetzt."""
    if booked_at:
        dt = frappe.utils.get_datetime(booked_at)  # akzeptiert ISO 'YYYY-MM-DD HH:MM:SS'
        # Plausibilität: nicht in der Zukunft
        if dt > now_datetime():
            dt = now_datetime()
        return dt
    return now_datetime()
```

### `clock_in(...)` — Signatur + Zeitstempel
- Parameter `booked_at: str | None = None` ergänzen.
- `now = now_datetime()` → `now = _stamp(booked_at)`

### `clock_out(employee, booked_at: str | None = None)`
- `entry.end_time = now_datetime().strftime(...)` → `entry.end_time = _stamp(booked_at).strftime(...)`
- Ebenso `entry.date`/Segmentende falls relevant.

### `pause(...)` / `resume(...)` (bzw. `_close` / `_start_from`)
- Diese schließen/öffnen Time Logs mit `now_datetime()`. Jeweils einen optionalen
  `booked_at` durchreichen und `_stamp(booked_at)` statt `now_datetime()` verwenden.

> Wichtig: **nur** den Zeitstempel ersetzen. Reihenfolge/Validierung (offene Buchung etc.)
> bleibt unverändert. Optional: `booked_at` in der Vergangenheit nur erlauben, wenn
> es nicht vor der letzten geschlossenen Buchung liegt (sonst überlappen Segmente).

---

## 2) `apex/workforce/mobile.py`

Alle self-service-Wrapper um `booked_at` erweitern und an `kiosk.*` durchreichen:

```python
@frappe.whitelist()
def book(cost_center=None, project_order=None, project_order_position=None,
         activity=None, latitude=None, longitude=None, employee=None,
         apply_team=0, booked_at: str | None = None):
    ...
    def _book_one(emp):
        if kiosk._open_entry(emp):
            kiosk.clock_out(emp, booked_at=booked_at)
        return kiosk.clock_in(emp, ..., source="Mobile", booked_at=booked_at)
    ...

@frappe.whitelist()
def clock_out(employee=None, apply_team=0, booked_at: str | None = None):
    return _apply_team_action(lambda e: kiosk.clock_out(e, booked_at=booked_at),
                              _target_employee(employee), apply_team)

@frappe.whitelist()
def pause(employee=None, apply_team=0, booked_at: str | None = None): ...
@frappe.whitelist()
def resume(employee=None, apply_team=0, booked_at: str | None = None): ...
```

(`clock_in` in mobile.py ebenfalls `booked_at` durchreichen, falls direkt genutzt.)

---

## Format des Zeitstempels
Die App schickt `booked_at` als **`YYYY-MM-DD HH:MM:SS`** in **Server-Zeit** (Europe/Berlin),
passend zu `frappe.utils.get_datetime`. (Die App rechnet lokale Gerätezeit → diese Form.)

## Test
- Online-Buchung **ohne** `booked_at` → verhält sich exakt wie bisher (jetzt-Zeit).
- Buchung **mit** `booked_at="2026-07-19 07:30:00"` → Time Log `start_time` = 07:30:00.
- `booked_at` in der Zukunft → wird auf jetzt begrenzt.

Wenn das steht, sag mir Bescheid — dann schickt die Flutter-App bei Offline-Nachbuchungen den
echten Zeitstempel mit, und Online-Buchungen bleiben unverändert.

---

# Optional (später): GPS-Pflicht serverseitig steuern — `use_gps`

Die App macht GPS aktuell **immer zur Pflicht** (kein Standort → kein Stempeln). Sie liest aber
bereits einen optionalen Schalter aus `get_me` → `config.use_gps`:

- **fehlt der Schlüssel** → GPS ist Pflicht (aktuelles Verhalten)
- `config.use_gps = false` → App macht GPS optional

Zum Steuern in `mobile.get_me` ergänzen (z. B. aus einem Feld an APX Employee oder den
Time-Tracking-Settings):

```python
status["config"]["use_gps"] = bool(s.get("require_gps"))  # oder doc.get("require_gps")
```

So lässt sich die GPS-Pflicht pro Mitarbeiter/global umschalten, ohne die App zu ändern.
