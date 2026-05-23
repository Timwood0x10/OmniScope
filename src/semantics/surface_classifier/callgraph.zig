//! Surface Classifier — Layer 3: CallGraph Reachability
//!
//! Reachability analysis is performed by SurfaceClassifierPass.run()
//! which has access to PassContext.CallSiteIndex for BFS traversal.
//!
//! This file is a placeholder for future extraction of the L3 logic
//! from the pass wrapper. Currently the BFS is inlined in the pass
//! for simplicity — it can be extracted here when the pass grows.
//!
//! The merge logic that consumes reachability results lives in
//! surface_classifier.zig::mergeLayers().

// L3 reachability is currently implemented inline in
// src/pass/analysis/surface_classifier_pass.zig::applyReachability().
// This file exists to document the layer boundary and can be
// populated when the pass logic needs further decomposition.
