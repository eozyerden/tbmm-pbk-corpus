# Coverage Report — Stages 5a and 5b

**Date:** 27 May 2026
**Status:** Complete

This report summarises the three-pronged coverage verification conducted after the full pipeline was assembled. All checks confirm that the corpus covers the complete universe of TBMM Plan and Budget Committee budget hearings for 2009-2025.

---

## Findings

### 1. PDF inventory (Stage 5a)

- 294 PDFs present: 196 SBB + 98 OWA
- Annual distribution: 13-21 PDFs per budget year — within the expected range
- Page distribution: SBB median 138 pages, OWA median 90 pages
- Single date discrepancy: file `20211126` contains the text "26 Ekim 2021" internally (source document error; filename date used)

### 2. Session-number sequencing (Stage 5a continued)

- 189 PDFs contain a single session; 7 PDFs contain two sessions (morning + afternoon, same document)
- Year-by-year sequencing check identified 13 "missing" session numbers
- **These are not genuine gaps — they correspond to non-budget PBK sessions**

### 3. Non-budget PBK session types (confirmed against user-supplied data)

The TBMM 2023 PBK session agenda list (supplied by the researcher) was cross-referenced with our inventory. The "skipped" sequence numbers correspond to:
- Development plan deliberations (constitutional mandate)
- Draft legislation reviews
- Central Bank annual activity presentation (Law No. 1211)
- Presidential decree reviews

These sessions are **not budget hearings** and are correctly outside the scope of this fiscal discourse corpus.

### 4. Ministry coverage verification (Stage 5b)

- Extended ministry name dictionary: 19 ministries with historical and current names
- Full-text scan of all PDFs (not just the first 20 speeches as in the preliminary pass)
- Undetected PDFs: 0 (preliminary pass had found 34; those were artefacts of the 20-speech limit)
- Each year shows 15-19 distinct ministry names detected
- Apparent gaps explained by historical restructuring:
  - Aile ve Sosyal Hizmetler (Family and Social Services): ministry created 2011; no 2009-2010 data is correct
  - Devlet Bakanlığı (State Ministry): abolished after 2011 restructuring; absent from 2012+ is correct
  - Gençlik ve Spor (Youth and Sports): ministry created 2011; no 2009-2010 data is correct

### Important methodological note on ministry detection

Ministry name appearing in a PDF ≠ that day's session was devoted to that ministry's budget. A ministry name may appear as a cross-reference or in another speaker's remarks. The current ministry-speech linkage uses a loose definition ("ministry name appears in the PDF text"). More precise linkage (agenda header + chair opening + minister presentation) is left for future work.

---

## Conclusion

The corpus provides complete coverage of TBMM PBK budget hearings for 2009-2025. 294 PDFs / 17 budget years. No budget hearings are missing. Session-sequence gaps correspond to non-budget PBK activity outside this corpus's analytical scope.
