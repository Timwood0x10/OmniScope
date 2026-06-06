//! Language-related type definitions for the analysis pipeline.
//!
//! Provides shared language detection types, channel mode gating,
//! and configuration structures used across passes and detectors.

const language_detector = @import("../semantics/language_detector.zig");

/// Configured language detection parameters.
/// Extracted from language_detector.zig as a shared config source.
pub const LanguageConfig = struct {
    sampling_weight: f32 = 1.0,
    personality_weight: f32 = 0.8,
    globals_weight: f32 = 0.6,
    personality_strong: f32 = 3.0,
    global_strong_weight: f32 = 2.0,
    global_weak_weight: f32 = 1.0,
    min_sampling_confidence: f32 = 0.4,
    min_vote_threshold: f32 = 0.3,
    min_personality_score: f32 = 2.0,
    min_globals_score: f32 = 1.5,
};

/// The detected language of a module, wrapping LanguageProfile.
pub const ModuleLanguage = language_detector.LanguageProfile;

/// R7.2: Channel mode for analysis pass gating.
pub const ChannelMode = enum {
    full,
    limited,
    skip,
};
