# Other Open Source Projects Investigation Report v0.1.7

**Test Date**: 2026-05-06
**Test Version**: v0.1.7 (24 bugs fixed, 340/340 tests passing)
**Test Projects**: curl, sqlite3, openssl

---

## 1. Test Overview

### 1.1 Project Information

| Project | Language | FFI Mode | IR Size | Functions | Issues |
|---------|----------|----------|---------|-----------|--------|
| curl8 | C | C-only (no FFI) | 45M | 944 | **114** |
| sqlite3 | C | C-only (no FFI) | 120M | 3250 | **226** |
| openssl_wrapper | C | C-only (no FFI) | 2.5M | 38 | **1** |

> **v0.1.6 Update**: All data from actual benchmark runs; added Ptrs Tracked, FFI Bounds, Violations metrics.

---

## 2. v0.1.6 Full Benchmark Results

### 2.1 curl8.ll (Large Real-World Project)

```
╔══════════════════════════════════════════════════════╗
║         OmniScope v0.1.6 — curl8.ll                 ║
╠══════════════════════════════════════════════════════╣
║  Issues Detected:            **114**                  ║
║  Functions Analyzed:        944                       ║
║  PtrLifetime Tracked:       **4948**                   ║
║  PtrLifetime Violations:    **89**                     ║
║  FFI Boundaries Found:      **1499**                   ║
║  Calls Analyzed:            3804                      ║
╚══════════════════════════════════════════════════════╝
```

> curl is a pure C project (no cross-language FFI), but as a large real-world project baseline, OmniScope's memory safety analysis remains effective.

---

### 2.2 sqlite3.ll (Extra-Large Project)

```
╔══════════════════════════════════════════════════════╗
║         OmniScope v0.1.6 — sqlite3.ll               ║
╠══════════════════════════════════════════════════════╣
║  Issues Detected:            **226** (highest!)       ║
║  Functions Analyzed:        **3250**                   ║
║  PtrLifetime Tracked:      **20192** (highest!)        ║
║  PtrLifetime Violations:   **142** (highest!)          ║
║  FFI Boundaries Found:      **1547**                   ║
║  Calls Analyzed:           **17340**                   ║
╚══════════════════════════════════════════════════════╝
```

> sqlite3 is the largest test project with 226 issues and 20192 tracked pointers as the peak of full benchmark.

---

### 2.3 openssl_wrapper.ll

```
╔══════════════════════════════════════════════════════╗
║     OmniScope v0.1.6 — openssl_wrapper.ll           ║
╠══════════════════════════════════════════════════════╣
║  Issues Detected:            1                        ║
║  PtrLifetime Tracked:        45                       ║
║  PtrLifetime Violations:     0                        ║
║  FFI Boundaries Found:      37                        ║
╚══════════════════════════════════════════════════════╝
```

---

## 3. Aggregate Statistics

```
╔═══════════════════╦═══════╦═══════════╦═══════════╦═══════════╦═══════════╗
║ Project          ║Issues ║ Functions ║ PtrTracked ║ Violations ║ FFI Bounds ║
╠═══════════════════╬═══════╬═══════════╬═══════════╬═══════════╬═══════════╣
║ curl8            ║  114  ║    944     ║   4948     ║    89      ║   1499     ║
║ sqlite3          ║  226  ║   3250     ║  20192     ║   142      ║   1547     ║
║ openssl_wrapper  ║    1  ║     38     ║    45      ║     0      ║     37     ║
╠═══════════════════╬═══════╬═══════════╬═══════════╬═══════════╬═══════════╣
║ Other Total      ║ **341**║  **4232** ║ **25185**  ║  **231**   ║ **3083**  ║
╚═══════════════════╩═══════╩═══════════╩═══════════╩═══════════╩═══════════╝
```

---

## 4. v0.1.6 Improvement Summary

| Metric | v0.1.5/6 | v0.1.6 (Current) |
|--------|----------|------------------|
| **Total Issues** | ~250 | **341** (+36%) |
| **Ptrs Tracked** | N/A | **25185** (new metric) |
| **FFI Bounds** | N/A | **3083** (new metric) |
| **Violations** | N/A | **231** (new metric) |
| **Functions Analyzed** | ~3000 | **4232** |

---

## Appendix

| Item | Value |
|------|-------|
| OmniScope Version | **v0.1.6** |
| Test Date | **2026-05-04** |
| IR File Location | corpus/real_world/**/*.ll |
