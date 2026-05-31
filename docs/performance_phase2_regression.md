# Performance Optimization Results - Phase 2

**Date:** 2026-05-31  
**Test File:** wasmtime_test.bc (5293 functions)

## Performance Results

| Phase | Time | Improvement | Notes |
|-------|------|-------------|-------|
| **Baseline** | 90s | - | Original |
| **Phase 1** | 73s | -18% | HashMap indices + reachability cache + prealloc + object pool |
| **Phase 2** | 82.1s | +12% ⚠️ | InstCache integration - **REGRESSION** |

## Analysis: Why Regression?

### Expected vs Actual

**Expected:** 67-69 seconds (5-8% improvement)  
**Actual:** 82.1 seconds (12% regression)  
**Delta:** +9-15 seconds slower than expected

### Root Cause Analysis

The InstCache integration caused a **performance regression** instead of improvement. Possible reasons:

1. **Cache Miss Overhead**
   - HashMap lookup overhead for cache misses
   - Memory allocation for cache entries
   - Cache is per-pass, not pre-warmed

2. **Memory Pressure**
   - InstCache adds ~20MB memory overhead
   - May cause more GC/allocation pressure
   - Cache HashMap operations add overhead

3. **FFI Call Pattern**
   - cross_lang_dataflow may not have enough repeated instruction access
   - Cache hit rate might be lower than expected 85-95%
   - First-time access now has HashMap overhead

4. **Implementation Issue**
   - Lazy cache population on first access
   - No pre-warming of cache
   - Each function starts with empty cache (cleared between functions?)

### Verification Needed

```bash
# Check if cache is being cleared too frequently
grep "clearRetainingCapacity\|clear()" src/pass/analysis/ffi/cross_lang_dataflow.zig

# Check actual cache hit rate (need to add logging)
# Expected in output: "CrossLangDataFlow: InstCache hit rate: XX.X%"
```

## Recommendation: Revert Phase 2

Since Phase 2 caused a regression, we should:

1. **Revert InstCache integration** in cross_lang_dataflow.zig
2. **Keep Phase 1 optimizations** (73 seconds is still 18% better than baseline)
3. **Focus on Phase 3** (traversal merging) which has higher ROI

### Alternative Approach

Instead of per-pass InstCache, implement **global instruction cache** at pipeline level:

```zig
// In Pipeline.zig
pub const Pipeline = struct {
    inst_cache: InstCache,  // Shared across all passes
    
    pub fn setModule(self: *Pipeline, module: Module) !void {
        self.inst_cache.clear();
        // Pre-warm cache with single traversal
        try self.inst_cache.warmup(module);
    }
};
```

This would:
- Eliminate per-pass cache initialization overhead
- Achieve true 85-95% hit rate across all passes
- Amortize cache building cost across all passes

## Corrected Performance Plan

| Phase | Optimization | Expected Time | Improvement |
|-------|-------------|---------------|-------------|
| Baseline | - | 90s | - |
| Phase 1 | ✅ Data structures | 73s | -18% |
| Phase 2 | ❌ InstCache (reverted) | 73s | 0% |
| Phase 3a | Traversal merging | 55s | -25% |
| Phase 3b | Global InstCache | 45s | -18% |
| Phase 3c | Function filtering | 37s | -18% |
| **Final** | **All optimizations** | **37s** | **59%** ✅

## Next Steps

1. **Revert Phase 2 changes** to get back to 73 seconds
2. **Implement Phase 3a** (traversal merging) - highest ROI
3. **Implement global InstCache** at pipeline level
4. **Add function pre-filtering**

## Lessons Learned

- ✅ Data structure optimizations (Phase 1) are effective
- ❌ Per-pass caching without pre-warming adds overhead
- 📊 Always measure before assuming optimization will help
- 🎯 Focus on algorithmic improvements (traversal merging) over micro-optimizations

## Files to Revert

```bash
git checkout src/pass/analysis/ffi/cross_lang_dataflow.zig
```

This will restore the Phase 1 optimizations (73 seconds) without the Phase 2 regression.
