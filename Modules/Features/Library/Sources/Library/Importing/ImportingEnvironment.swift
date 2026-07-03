//
//  ImportingEnvironment.swift
//  Library
//
//  SwiftUI environment keys for the import layer, injected by the composition root (Core)
//  — mirrors the existing \.playlistLibraryStore pattern so views stay decoupled from Core.
//

import SwiftUI

public extension EnvironmentValues {
    @Entry var importDownloadManager: ImportDownloadManager?

    @Entry var importProgressFacade: ImportProgressFacade? = nil
}
