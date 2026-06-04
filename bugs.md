---
  Code Review Results
     
  🔴 Critical — Breaks documented behavior 
     
  1. Missing sortPrefixRules() / sortSuffixRules() after CLI loop (src/main.zig ~line 131)
  
  addPrefix()'s own docstring says "call sortPrefixRules() after all additions," but the CLI loop in main.zig never calls it. The lookup() function iterates in insertion order, so --lang-prefix sqlite3_=c --lang-prefix sqlite3_open_=rust will
  match the shorter prefix first and return wrong results. loadFromJson() and mergeFromCLI() both sort — only this path forgets.
  
  2. std.meta.stringToEnum rejects all documented aliases (src/main.zig ~line 117)
  
  The Language enum tags are cpp, python, csharp, but parseLangString() — which exists precisely to handle aliases — also accepts c++, py, c#. main.zig uses stringToEnum instead, so those CLI values silently continue with zero diagnostic. --lang
   foo=c++ is a silent no-op.
  
  Fix: call language_override.LanguageOverrideRegistry.parseLangString(kv.value) instead of std.meta.stringToEnum.
  
  ---
  🟠 High — Documented use cases silently non-functional

  3. --default-lang has no effect in danger_surface.zig (src/pass/analysis/danger_surface.zig ~line 146)

  The cross-lang lifecycle suppression block calls reg.lookup(alloc_callee) but never reg.getDefault(). The primary sqlite3 FP (documented in P0) requires --default-lang c to work — but if the user passes only --default-lang c with no prefix
  rules, lookup() returns null, registry_suppressed stays false, and the FP fires. The feature silently does nothing for this case.
  
  4. --default-lang has no effect in ffi_unsafe.zig (src/pass/analysis/issue/ffi_unsafe.zig ~line 181)
  
  Same root cause: the same-language skip requires caller_lang AND callee_lang both non-null from lookup(). If neither function is in a specific rule, both return null, the entire block is dead. The 2,611 ffi_unsafe_call FPs remain unchanged
  under --default-lang c. 
  
  Both fixes are the same: substitute reg.lookup(name) orelse reg.getDefault().
  
  5. --source-lang feature is wired to the registry but never consulted by any pass (src/config/language_override.zig:lookupSourceFile)
  
  lookupSourceFile() has no callers outside tests. --source-lang parses fine, builds the source_file_map correctly, but zero analysis passes call lookupSourceFile(). Scenario 3 from the design doc is a complete no-op end-to-end.
  
  ---
  🟡 Medium — Memory safety
  
  6. mergeFromCLI leaks the old duped key on overwrite (src/config/language_override.zig ~line 315)
  
  self.exact_map.remove(entry[0]) removes the old entry without freeing the previously-duped key. deinit() only iterates the current map state, so the orphaned string leaks. Same pattern in addSourceFile if called twice for the same filename —
  put overwrites the value, the first duped key is unreachable and leaked.
  
  Fix: use fetchRemove() to capture and free the old key before inserting the replacement.
  
  ---
  🔵 Low — Semantic gap
  
  7. pass_types.zig default-lang fallback only fires when detector returns .unknown (src/types/pass_types.zig ~line 862)
  
  The comment says "when auto-detection confidence is low" but the code checks language == .unknown. Any well-formed IR returns a concrete language with reasonable confidence, so --default-lang rust is a no-op when you're trying to override a
  wrong high-confidence detection. This is an accuracy gap for the module-level reclassification use case.
  
  ---
  Summary table
  
  ┌─────┬───────────────────────┬─────────────┬─────────────────────────────────────────────────────────────────────────────────┐
  │  #  │         File          │  Severity   │                                      Issue                                      │
  ├─────┼───────────────────────┼─────────────┼─────────────────────────────────────────────────────────────────────────────────┤
  │ 1   │ main.zig              │ 🔴 Critical │ Missing sortPrefixRules()/sortSuffixRules() after CLI loops                     │
  ├─────┼───────────────────────┼─────────────┼─────────────────────────────────────────────────────────────────────────────────┤
  │ 2   │ main.zig              │ 🔴 Critical │ stringToEnum rejects c++/py/c# aliases silently                                 │
  ├─────┼───────────────────────┼─────────────┼─────────────────────────────────────────────────────────────────────────────────┤
  │ 3   │ danger_surface.zig    │ 🟠 High     │ getDefault() never consulted — --default-lang c has no effect on cross-lang FPs │
  ├─────┼───────────────────────┼─────────────┼─────────────────────────────────────────────────────────────────────────────────┤
  │ 4   │ ffi_unsafe.zig        │ 🟠 High     │ getDefault() never consulted — --default-lang c cannot suppress 2611 reports    │
  ├─────┼───────────────────────┼─────────────┼─────────────────────────────────────────────────────────────────────────────────┤
  │ 5   │ language_override.zig │ 🟠 High     │ --source-lang builds map but lookupSourceFile() has zero callers in passes      │
  ├─────┼───────────────────────┼─────────────┼─────────────────────────────────────────────────────────────────────────────────┤
  │ 6   │ language_override.zig │ 🟡 Medium   │ mergeFromCLI + duplicate addSourceFile leak the old duped key string            │
  ├─────┼───────────────────────┼─────────────┼─────────────────────────────────────────────────────────────────────────────────┤
  │ 7   │ pass_types.zig        │ 🔵 Low      │ default-lang override blocked by any non-.unknown detector result               │
  └─────┴───────────────────────┴─────────────┴─────────────────────────────────────────────────────────────────────────────────┘
  
  Items 1 and 2 are the most impactful — they affect basic CLI operation. Items 3 and 4 mean the headline P0 use case (--default-lang c) produces no visible effect without additional explicit prefix rules. Item 5 means Scenario 3 (--source-lang)
   is dead code. Want me to fix these?
