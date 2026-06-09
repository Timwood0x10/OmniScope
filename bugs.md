Code Review Round 2
  
  🔴 Critical — Feature completely dead
  
  8. --config JSON overrides are end-to-end non-functional (src/types/file_config.zig:111)
  
  file_config.zig:loadFromFile() is still the TODO stub that returns FileConfig{} empty. main.zig's config_path block explicitly says // JSON overrides could be loaded here in the future. So omniscope --config myfile.json logs "Loaded
  configuration from..." but zero overrides are applied. The loadFromJson() method and all its unit tests are correct but completely unreachable in production.
  
  9. run_full_test.sh — safe_grep_count -i silently measures nothing (run_full_test.sh:107)
  
  The function signature is safe_grep_count $1 $2, where $1=pattern and $2=file. But callers pass it as safe_grep_count -i 'PATTERN' "$out" — making $1="-i" (the literal flag) and $2 the pattern (interpreted as filename). grep fails, || true
  masks it, and ${cl:=0} forces the count to 0. Every row in phase1_baseline.csv and phase2_override.csv has cross_lang=0, ownership=0, danger=0, ffi_type=0. The override comparison numbers are fabricated zeros.
  
  ---
  🟠 High — Incomplete override coverage
  
  10. call_graph.zig classifies cross-lang edges without override (src/pass/analysis/call_graph.zig:411)
  
  CallGraphPass builds the CrossLangEdge list using identifyCalleeLanguage (the non-context version, no override). Even if cross_lang_dataflow.zig respects --lang __rust_alloc=rust, call_graph will still emit a CrossLangEdge for it, and
  downstream passes that consume edges (including DangerSurfacePass's FFI boundary set) re-process the FP.
  
  11. ffi_boundary_check.zig has a ffi_reentry check with no override (src/pass/analysis/ffi/ffi_boundary_check.zig:292)
  
  A direct call to identifyCalleeLanguage(callee_name) != .c — no ctx, no override. A user's --lang wrapper_cb=c is respected by ffi_boundary.zig but ignored by this check in the same pass group. Same symbol gets two contradicting answers.
  
  12. classifyFreeLanguage always called with caller_lang = .unknown — fallback is dead (src/pass/analysis/ffi/cross_lang_dataflow.zig:~1371)
  
  Both free classification call sites hard-code caller_lang = .unknown. The function's final fallback return caller_lang was designed to default to the caller's language for unrecognized custom deallocators — but with .unknown always passed,
  every unrecognized free returns .unknown instead of the caller's actual language. This means custom deallocators like my_arena_free in a Rust module will never get classified as .rust. The diff preserved and re-annotated the pre-existing bug
  without fixing it.
  
  ---
  🟡 Medium — Test / tooling correctness
  
  13. run_full_test.sh — hardcoded /Users/scc/ absolute paths + no set -e (run_full_test.sh:17)
  
  10 test fixture paths are absolute paths to another machine's home directory. Combined with missing -e flag (only -uo pipefail), failures silently produce PARSE_FAIL rows in the CSV and the script exits 0. CI gets green with a corrupted
  baseline. 
  
  14. --source-lang untested and never exercised by run_full_test.sh (run_full_test.sh:76)
  
  get_override_args builds --default-lang, --lang-prefix, --lang — but never --source-lang. Given that lookupSourceFile() has no callers in any analysis pass (found in Round 1), the test suite cannot detect that the entire Scenario 3 feature is
  dead.
  
  ---
  Summary table (both review rounds combined)
  
  ┌─────┬───────────────────────────────┬──────────┬─────────────────────────────────────────────────────────────────────────────┐
  │  #  │             File              │ Severity │                                    Issue                                    │
  ├─────┼───────────────────────────────┼──────────┼─────────────────────────────────────────────────────────────────────────────┤
  │ 1   │ main.zig                      │ 🔴       │ Missing sortPrefixRules()/sortSuffixRules() after CLI loops                 │
  ├─────┼───────────────────────────────┼──────────┼─────────────────────────────────────────────────────────────────────────────┤
  │ 2   │ main.zig                      │ 🔴       │ stringToEnum rejects c++/py/c# aliases silently                             │
  ├─────┼───────────────────────────────┼──────────┼─────────────────────────────────────────────────────────────────────────────┤
  │ 3   │ danger_surface.zig            │ 🟠       │ getDefault() not consulted — --default-lang c can't suppress cross-lang FPs │
  ├─────┼───────────────────────────────┼──────────┼─────────────────────────────────────────────────────────────────────────────┤
  │ 4   │ ffi_unsafe.zig                │ 🟠       │ getDefault() not consulted — 2611 reports unaffected by --default-lang      │
  ├─────┼───────────────────────────────┼──────────┼─────────────────────────────────────────────────────────────────────────────┤
  │ 5   │ language_override.zig         │ 🟠       │ --source-lang builds map but lookupSourceFile() has zero pass callers       │
  ├─────┼───────────────────────────────┼──────────┼─────────────────────────────────────────────────────────────────────────────┤
  │ 6   │ language_override.zig         │ 🟡       │ mergeFromCLI + duplicate addSourceFile leak the old duped key string        │
  ├─────┼───────────────────────────────┼──────────┼─────────────────────────────────────────────────────────────────────────────┤
  │ 7   │ pass_types.zig                │ 🔵       │ --default-lang blocked by any non-.unknown detector result                  │
  ├─────┼───────────────────────────────┼──────────┼─────────────────────────────────────────────────────────────────────────────┤
  │ 8   │ file_config.zig:111           │ 🔴       │ --config JSON override path is a TODO stub — entire JSON feature dead       │
  ├─────┼───────────────────────────────┼──────────┼─────────────────────────────────────────────────────────────────────────────┤
  │ 9   │ run_full_test.sh:107          │ 🔴       │ safe_grep_count -i arg order wrong — all comparison metrics record 0        │
  ├─────┼───────────────────────────────┼──────────┼─────────────────────────────────────────────────────────────────────────────┤
  │ 10  │ call_graph.zig:411            │ 🟠       │ Cross-lang edge detection ignores override registry                         │
  ├─────┼───────────────────────────────┼──────────┼─────────────────────────────────────────────────────────────────────────────┤
  │ 11  │ ffi_boundary_check.zig:292    │ 🟠       │ ffi_reentry check uses no-context classifier — contradicts ffi_boundary.zig │
  ├─────┼───────────────────────────────┼──────────┼─────────────────────────────────────────────────────────────────────────────┤
  │ 12  │ cross_lang_dataflow.zig:~1371 │ 🟡       │ classifyFreeLanguage always receives .unknown caller — fallback is dead     │
  ├─────┼───────────────────────────────┼──────────┼─────────────────────────────────────────────────────────────────────────────┤
  │ 13  │ run_full_test.sh:17           │ 🟡       │ Hardcoded absolute paths + no set -e — CI false-positive                    │
  ├─────┼───────────────────────────────┼──────────┼─────────────────────────────────────────────────────────────────────────────┤
  │ 14  │ run_full_test.sh:76           │ 🔵       │ --source-lang never tested                                                  │
  └─────┴───────────────────────────────┴──────────┴─────────────────────────────────────────────────────────────────────────────┘
  
  Items 1, 2, 8, 9 are the highest-priority fixes — each silently breaks a documented use case. Want me to start fixing them?
