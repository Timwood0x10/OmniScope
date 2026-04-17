# OmniScope Benchmark Suite

Professional performance benchmarking for LLVM IR static analysis.

## Quick Start

```bash
make bench
```

## Benchmark Categories

### 1. Component Benchmarks
- **FactStore** - Fact insertion and query performance
- **TaintContext** - Taint tracking operations
- **FFIBoundary** - FFI boundary detection
- **FlowPath** - Data flow path construction
- **RiskLevel** - Risk classification

### 2. Pipeline Benchmarks
- **Full Pipeline** - End-to-end analysis
- **IR Loading** - LLVM IR parsing
- **Pass Execution** - Individual pass performance

### 3. Scale Benchmarks
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
Engine Alloc: 24.66ms total, 2466.00ns/iter (10000 iterations)
...
```

### JSON Report
```json
{
  "timestamp": 1234567890,
  "benchmark_name": "OmniScope Benchmark Suite",
  "results": [
    {
      "test_name": "FactStore Insert 100000 items",
      "avg_ms": 45.2,
      "min_ms": 42.1,
      "max_ms": 48.9,
      "stddev_ms": 2.1,
      "p50_ms": 45.0,
      "p95_ms": 47.5,
      "p99_ms": 48.2,
      "avg_memory_bytes": 1048576,
      "min_memory_bytes": 983040,
      "max_memory_bytes": 1114112
    }
  ]
}
```

### CSV Report
```csv
test_name,avg_ms,min_ms,max_ms,stddev_ms,p50_ms,p95_ms,p99_ms,avg_memory_bytes
FactStore Insert,45.2,42.1,48.9,2.1,45.0,47.5,48.2,1048576
```

## Performance Targets

| Component | Target | Notes |
|-----------|--------|-------|
| FactStore Insert | < 1μs/fact | 1M facts in < 1s |
| FactStore Query | < 10μs/query | O(n) scan acceptable |
| Taint Tracking | < 100ns/value | Hash map lookup |
| FFI Detection | < 50ns/call | Pattern matching |
| Full Pipeline | < 1s/1K funcs | Linear scaling |

## Memory Targets

| Scale | Target Memory | Notes |
|-------|---------------|-------|
| Small | < 50MB | Fits in L3 cache |
| Medium | < 200MB | Fits in RAM |
| Large | < 1GB | Streaming mode |

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
