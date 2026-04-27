# Other Projects Investigation Report v0.1.5

**Test Date**: 2026-04-25
**Test Version**: v0.1.5 (Zone Classification)

---

## 1. ark-ff (Rust Finite Field Library)

### 1.1 Zone Classification Results

```
  Total functions analyzed:    16
  Safe zone (skipped):         1 (18.8%)
  Runtime internal (skipped):  2
  Unknown zone:                13

  Issues found:                0
```

### 1.2 Analysis

- Small project, few functions
- Pure Rust implementation, no FFI
- 0 issues

---

## 2. libsodium (C Cryptography Library)

### 2.1 Zone Classification Results

```
  Total functions analyzed:    10
  Safe zone (skipped):         0 (0.0%)
  Runtime internal (skipped):  0
  Unknown zone:                10

  Issues found:                0
```

### 2.2 Analysis

- Pure C project, no language guarantees
- All functions need analysis
- libsodium has good memory management, 0 issues

---

## 3. gnark-crypto (Go Cryptography Library)

### 3.1 Zone Classification Results

```
  Total functions analyzed:    838
  Safe zone (skipped):         250 (29.8%)
  Runtime internal (skipped):  0
  Unknown zone:                588

  Issues found:                1
```

### 3.2 Analysis

- Go project, compiled with tinygo
- Needs enhanced Go pattern recognition
- 1 issue from tinygo runtime

---

## 4. ripgrep (Rust Search Tool)

### 4.1 Zone Classification Results

```
  Total functions analyzed:    30
  Safe zone (skipped):         6 (46.7%)
  Runtime internal (skipped):  8
  Unknown zone:                16

  Issues found:                0
```

### 4.2 Analysis

- Pure Rust project
- 46.7% skip rate
- 0 issues

---

## 5. rust-sqlite (Rust SQLite Binding)

### 5.1 Zone Classification Results

```
  Total functions analyzed:    17
  Safe zone (skipped):         5 (52.9%)
  Runtime internal (skipped):  4
  Unknown zone:                8

  Issues found:                6
```

### 5.2 Analysis

- Rust FFI project
- 8 unknown functions are FFI boundaries
- 6 issues from FFI memory management

---

## 6. Summary

| Project | Language | Functions | Skip % | Issues |
|---------|----------|-----------|--------|--------|
| ark-ff | Rust | 16 | 18.8% | 0 |
| libsodium | C | 10 | 0% | 0 |
| gnark-crypto | Go | 838 | 29.8% | 1 |
| ripgrep | Rust | 30 | 46.7% | 0 |
| rust-sqlite | Rust FFI | 17 | 52.9% | 6 |

---

## 7. Appendix

| Item | Value |
|------|-------|
| OmniScope Version | v0.1.5 |
| Test Date | 2026-04-25 |
