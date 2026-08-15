//
//  Exports.swift
//  Player
//
//  Re-exports PlaybackCore so consumers need a single import.
//

// PlaybackCore is split out purely so the playback logic stays testable with `swift test` — see
// Package.swift. That is a build-system concern, not something call sites should have to know
// about, so `import Player` brings the whole surface with it.
@_exported import PlaybackCore
