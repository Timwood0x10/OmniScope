//! Graph Algorithms — Consolidated Single Source of Truth
//!
//! Re-exports from dataflow/graph_algorithms.zig (SSOT).
//! This file exists for backward compatibility.

const graph_algo = @import("../dataflow/graph_algorithms.zig");

pub const FlowGraph = graph_algo.FlowGraph;
pub const FlowGraphAlloc = graph_algo.FlowGraphAlloc;
pub const canReach = graph_algo.canReach;
pub const findFreePath = graph_algo.findFreePath;
pub const canReachFree = graph_algo.canReachFree;
pub const addFlowEdge = graph_algo.addFlowEdge;
pub const hashValues = graph_algo.hashValues;
