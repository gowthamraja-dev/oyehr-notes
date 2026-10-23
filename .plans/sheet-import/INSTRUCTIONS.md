# Prompt for a Claude Code session that has Google Sheets edit access

Paste everything below the line into that session.

---

Add new rows to the Google Sheet **HRMS-CHANGES-TRACKER**
(https://docs.google.com/spreadsheets/d/1Bobet5olcyh9ImzoXJJETehvO1UtrwmaTtxdgf9qKag/edit, tab with gid=338184771),
assign them to me, and colour the Status cells to match the existing rows.

**Source files** (tab-separated, no header row, already in the sheet's column order):
- `/Users/ntguy/oyehr/.plans/sheet-import/change_register_rows.tsv`: 22 rows, CR-116 to CR-137, 10 columns:
  Change ID, Module, Change Request, Detailed Requirement, Priority, Assigned To, Status, Source / Note, Start Date, End Date.
- `/Users/ntguy/oyehr/.plans/sheet-import/defects_rows.tsv`: 19 rows, CR-138 to CR-156, 6 columns:
  ID / Report ref, Severity, Issue, Priority, Assigned To, Status.

**Do this in order:**
1. **Read first, write nothing yet.** Find the header row of the Change Register and of the Defects section. Confirm the column order matches the files above. If it differs, stop and tell me instead of guessing.
2. **Check for clashes.** Confirm that CR-116 to CR-156 are unused. If any exist, stop and tell me.
3. **Learn the existing colours.** Read the background fill of the Status cells that are already in the sheet for each value (Completed, In Progress, Hold, Not Started) and reuse exactly those colours. Only if a value has no existing fill, use this fallback:
   Completed `#C6EFCE` (green), In Progress `#FFEB9C` (amber), Not Started `#E7E6E6` (light grey), Hold `#F8CBAD` (orange).
   Also check whether Priority has colours and copy them the same way.
4. **Insert the register rows.** Insert 22 blank rows directly above the Defects header row, so the Change Register stays above it, then write `change_register_rows.tsv` into them. Do not overwrite anything.
5. **Append the defect rows.** Write `defects_rows.tsv` into the first empty rows after the last defect (currently CR-115).
6. **Assigned To.** Set the Assigned To cell of every new row (both sections) to **Gowtham**, replacing "Owner to be assigned". (Confirm this spelling against how my name appears elsewhere in the sheet; if it is spelled differently, use that.)
7. **Formatting.**
   - Copy cell format, borders, fonts, number formats and any dropdown (data validation) from the row above each new block, so the rows look native.
   - Colour each new row's **Status** cell by its value using the colours from step 3.
   - Do not change any existing row's content or colours.
8. **Verify and report.** Read back the new rows and check: the count (22 and 19), no column shift, the IDs run CR-116 to CR-156, every Assigned To is my name, every Status colour matches its value. Tell me anything that did not apply.

**Rules:** only add rows. Do not delete, reorder or edit existing rows, other tabs, or sharing settings. If anything is ambiguous or a write fails partway, stop and report exactly what was written so far.
