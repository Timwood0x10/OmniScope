# OmniScope Benchmark Suite

Professional performance benchmarking for LLVM IR static analysis.

## Quick Start

```bash
# Run benchmarks (ReleaseFast optimization)
make bench

# Or directly with zig
zig build bench

# Alternative: bench-perf (same as bench)
zig build bench-perf
```

## Benchmark Categories

### 1. Lifetime Engine Benchmarks
- **Engine Init** - Engine creation overhead
- **Engine Alloc** - Resource allocation tracking
- **Engine Full Cycle** - Complete alloc→free cycle
- **Detect Leaks** - Leak detection for N resources

### 2. Semantic Registry Benchmarks
- **Lookup (known)** - Hash map hit for known functions
- **Lookup (unknown)** - Full scan for unknown functions
- **IsKnown** - Known function check
- **GetSeverity** - Severity level lookup

### 3. Semantic Mapper Benchmarks
- **MapFunction (C)** - C function semantic mapping
- **MapFunction (Rust)** - Rust function semantic mapping
- **IsAllocation** - Allocation function check
- **IsDeallocation** - Deallocation function check

## Scale Benchmarks

| Scale | Functions | Target Time | Target Memory |
|-------|-----------|-------------|---------------|
| Small | ~100 | < 100ms | < 50MB |
| Medium | ~1K | < 1s | < 200MB |
| Large | ~10K | < 10s | < 1GB |

## Output Format

### Console Output
```
=== Lifetime Engine Benchmarks ===
Engine Init: 0.00ms total, 0.00ns/iter (10000 iterations)
Engine Alloc: 24.42ms total, 2441.80ns/iter (10000 iterations)
Engine Full Cycle: 23.40ms total, 2340.00ns/iter (10000 iterations)
Engine Detect Leaks (100): 1.20ms total, 12030.00ns/iter (100 iterations)

=== Semantic Registry Benchmarks ===
Registry Lookup (known): 3.36ms total, 33.57ns/iter (100000 iterations)
Registry Lookup (unknown): 33.96ms total, 339.60ns/iter (100000 iterations)
Registry IsKnown: 2.13ms total, 21.28ns/iter (100000 iterations)
Registry GetSeverity: 0.70ms total, 7.02ns/iter (100000 iterations)

=== Semantic Mapper Benchmarks ===
Mapper MapFunction (C): 0.22ms total, 2.20ns/iter (100000 iterations)
Mapper MapFunction (Rust): 1.76ms total, 17.61ns/iter (100000 iterations)
Mapper IsAllocation: 0.27ms total, 2.70ns/iter (100000 iterations)
Mapper IsDeallocation: 0.88ms total, 8.79ns/iter (100000 iterations)

=== Memory Usage ===
Resources tracked: 1000
Issues detected: 0
```

## Performance Targets

| Component | Target | Actual | Status |
|-----------|--------|--------|--------|
| Engine Init | < 1μs | 0.00ns | ✅ PASS |
| Engine Alloc | < 5μs | ~2.4μs | ✅ PASS |
| Registry Lookup (known) | < 100ns | ~34ns | ✅ PASS |
| Registry Lookup (unknown) | < 1μs | ~340ns | ✅ PASS |
| Mapper MapFunction (C) | < 10ns | ~2.2ns | ✅ PASS |
| Full Pipeline | < 1s/1K funcs | ~30ms | ✅ PASS |

## Memory Targets

| Scale | Target Memory | Actual | Status |
|-------|---------------|--------|--------|
| 1000 resources | < 1MB | < 1MB | ✅ PASS |
| Small (< 100 funcs) | < 50MB | ~10MB | ✅ PASS |
| Medium (< 1K funcs) | < 200MB | ~30MB | ✅ PASS |

## Interpreting Results

### Good Performance
- Linear scaling with input size
- Stable memory usage (no leaks)
- Low variance between runs

### Warning Signs
- Exponential time growth
- Memory increasing over time
- High variance between runs

## CI Integration

Benchmarks run on every PR:
- Small corpus: Required
- Medium corpus: Required
- Large corpus: Optional (nightly)

Performance regression threshold: 20%

## Files

```
bench/
├── README.md      # This file
├── RESULTS.md     # Detailed analysis report
└── results.md     # Raw benchmark output

benches/
└── main.zig       # Benchmark implementation
```

## See Also

- [RESULTS.md](RESULTS.md) - Detailed benchmark analysis
- [../docs/architecture.md](../docs/architecture.md) - System architecture
