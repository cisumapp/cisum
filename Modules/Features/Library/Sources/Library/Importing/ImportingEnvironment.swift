//
//  ImportingEnvironment.swift
//  Library
//
//  SwiftUI environment keys for the import layer, injected by the composition root (Core)
//  — mirrors the existing \.playlistLibraryStore pattern so views stay decoupled from Core.
//

import SwiftUI

public struct ImportDownloadManagerKey: EnvironmentKey {
    public static let defaultValue: ImportDownloadManager? = nil
}

public struct ImportProgressFacadeKey: EnvironmentKey {
    public static let defaultValue: ImportProgressFacade? = nil
}

public extension EnvironmentValues {
    var importDownloadManager: ImportDownloadManager? {
        get { self[ImportDownloadManagerKey.self] }
        set { self[ImportDownloadManagerKey.self] = newValue }
    }
    var importProgressFacade: ImportProgressFacade? {
        get { self[ImportProgressFacadeKey.self] }
        set { self[ImportProgressFacadeKey.self] = newValue }
    }
}
