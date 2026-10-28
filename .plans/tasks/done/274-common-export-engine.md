---
task: 274
title: Common export engine (backend)
status: done
depends_on: []
---

# 274 — Common export engine (backend)

## Scope
The reusable half of exports, mirroring `app/modules/file_import/`. A report type is one `ExportHandler`; the engine owns request parsing,
RBAC, limits, CSV/XLSX serialisation, filename, headers and the audit row. **No report content here** (275–278) and **no frontend** (279).
**No new tables or migration** — exports are generated on request and never stored (see `.plans/attendance-export-plan.md`).

### Contract
```python
@dataclass(frozen=True)
class ColumnSpec:
    key: str; label: str
    kind: Literal["text", "int", "decimal", "date", "time", "duration"] = "text"
    width: int | None = None          # xlsx column width hint

@dataclass
class ExportTable:                    # what a handler returns
    title: str                        # sheet name / filename stem
    columns: list[ColumnSpec]
    rows: Iterable[Sequence[Any]]     # values already in display form
    meta: list[tuple[str, str]] = []  # "Period", "Filters", "Generated" … rendered as a header block (xlsx) / skipped (csv)
    legend: list[tuple[str, str]] = []# code → meaning; xlsx second sheet "Legend", skipped in csv
    group_header: list[tuple[str, int]] | None = None  # optional merged header band, e.g. month → span

class ExportHandler:
    export_type: str; resource: str; prefix: str; tag: str
    formats = ("csv", "xlsx")
    def parse_params(self, db, principal, raw: dict) -> BaseModel: ...   # validate + scope checks (raises 422/403)
    def build(self, db, principal, params) -> ExportTable: ...
    def audit(self, db, principal, params, table) -> None: ...           # best-effort, never raises
```
* Routes per handler (built by `router_factory.build_router(handler)`): `GET {prefix}/{export_type}?format=csv|xlsx&…handler params` →
  `Response` with `Content-Disposition: attachment; filename="<stem>-<from>_to_<to>.<ext>"`, `X-Content-Type-Options: nosniff`.
  Also `GET {prefix}` → the list of report types the caller may run (`[{export_type, label, description, formats, params_schema}]`) so the
  frontend dialog is data-driven (279).
* Plain `APIRouter` (binary body) — same reasoning as `attendance/router.py::_export_router`. Gate with
  `require_grid_permission(db, principal, "READ", handler.resource)` (or the attendance module's own `_READ` dependency for the ATTENDANCE
  handlers — match whatever 275 needs; a role with no saved grid must behave the same as today's `/register/export`).
* Writers (`writers.py`): `to_csv(table) -> bytes` (UTF-8 **with BOM** so Excel opens it; `csv.writer`; header = labels) and
  `to_xlsx(table) -> bytes` using `openpyxl` (already a dependency) in `write_only` mode: meta block, optional merged group header, bold
  frozen header row + frozen first columns (`freeze_panes`), column widths, numeric cells stay numeric (`decimal`/`int`), `duration` →
  `H:MM` text, legend on a second sheet.
* **Formula-injection guard** in one place: any text cell starting with `=`, `+`, `-`, `@`, tab or CR is prefixed with `'` (CSV and XLSX).
  Numbers are never touched.
* **Limits** (`limits.py`): `MAX_CELLS = 250_000` (rows × columns); handlers call `limits.check_cells(n_rows, n_cols)` before materialising →
  422 `"Too many rows for one export — narrow the date range or filters"`. Row iterables are consumed once, so a handler may stream.
* Registry: `handlers.register(...)` + `_LAZY` map (export_type → module) exactly like `file_import/handlers.py`, so one place lists every
  export; `app/api/router.py` mounts each handler's router.
* Tenant scoping is the handler's job and the engine's `ExportHandler.build` signature always passes `principal` — document and test that a
  handler never reads without `principal.tenant_id`.
* Logging: `structlog.get_logger(__name__)`; `export_generated` INFO with `export_type`, `format`, `rows`, `cols`, `tenant_id` — **never** cell
  values, names or filters containing search text.
* The audit hook is per-handler because audit tables are per-module (attendance uses `AttendanceAuditLog`, see the current
  `export_register_csv` for the "actor may have no EmployeeMaster" degradation).

## Files
* `backend/app/modules/file_export/__init__.py`, `handlers.py` (base class, `ColumnSpec`, `ExportTable`, registry/`_LAZY`), `writers.py`,
  `limits.py`, `router_factory.py`, `schemas.py` (catalogue response)
* `backend/app/api/router.py` (mount hook — mounting of concrete handlers arrives in 275+)
* `backend/app/tests/modules/test_file_export_engine.py` — proves the engine with a **fake** handler, as `test_file_import_engine.py` does

## Acceptance criteria
- [ ] A fake handler registered in the test returns CSV and XLSX; both re-parse (csv module / `openpyxl.load_workbook`) to the same grid
- [ ] CSV starts with a UTF-8 BOM; XLSX has meta block, frozen header, legend sheet, numeric cells numeric
- [ ] Cells `=SUM(A1)`, `+1`, `-1+1`, `@x` are written as text prefixed with `'`; a plain number `-5` stays numeric
- [ ] `format=pdf` → 422; unknown `export_type` → 404; over `MAX_CELLS` → 422 with the narrow-your-filters message
- [ ] Catalogue endpoint lists only the types the caller may run; a caller without READ gets 403
- [ ] `Content-Disposition` filename is sanitised (no path chars, no CRLF) and includes the period
- [ ] No handler can be added without `principal` reaching `build` (signature-level), and a cross-tenant test with the fake handler passes
- [ ] No PII/cell values in logs
- [ ] `uv run pytest app/tests/modules/test_file_export_engine.py` green

Completed: 2026-10-27
