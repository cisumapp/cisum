import Foundation
import Observation
import ProviderSDK
import Utilities

@Observable
@MainActor
public final class ProviderManifestStore {
    public static let shared = ProviderManifestStore()

    private enum Constants {
        static let folderName = "cisum"
        static let fileName = "provider-manifests.json"
    }

    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public private(set) var manifests: [ProviderManifest]
    public private(set) var lastStatusMessage: String?
    public private(set) var lastErrorMessage: String?
    public private(set) var enabledProviderIDs: Set<String>
    private var didReconcile = false

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.manifests = []
        self.enabledProviderIDs = Self.loadEnabledProviderIDs()

        PerfLog.info("Initializing ProviderManifestStore storage_path: \(storageURL.path)")

        Task {
            do {
                self.manifests = try await Self.loadManifests(from: fileManager, decoder: decoder)
                if enabledProviderIDs.isEmpty, !manifests.isEmpty {
                    self.enabledProviderIDs = Set(manifests.map(\.id))
                    Self.saveEnabledProviderIDs(enabledProviderIDs)
                }
                PerfLog.info("Loaded persisted manifests count: \(String(manifests.count)), storage_path: \(storageURL.path)")
            } catch {
                self.manifests = []
                self.lastErrorMessage = "Failed to load saved manifests: \(error.localizedDescription)"
                PerfLog.error("Failed to load persisted manifests error: \(error.localizedDescription), storage_path: \(storageURL.path)")
            }
        }
    }

    public var manifestCount: Int {
        manifests.count
    }

    public var storageURL: URL {
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return applicationSupportURL
            .appendingPathComponent(Constants.folderName, isDirectory: true)
            .appendingPathComponent(Constants.fileName)
    }

    public func importManifest(from url: URL) async throws -> ProviderManifest {
        PerfLog.info("Importing manifest url: \(url.absoluteString)")
        let sourceURL = try resolvedSourceURL(for: url)
        let data = try await loadRemoteData(from: sourceURL)
        PerfLog.debug("Loaded manifest payload source_url: \(sourceURL.absoluteString), byte_count: \(String(data.count))")

        let loader = ProviderManifestLoader()
        var manifest = try loader.load(from: data)
        manifest.source = sourceURL.isFileURL ? .local : .remote(url: sourceURL)

        enabledProviderIDs.insert(manifest.id)
        Self.saveEnabledProviderIDs(enabledProviderIDs)
        try upsert(manifest)
        try await register(manifest)

        lastStatusMessage = "Imported \(manifest.name)"
        lastErrorMessage = nil
        PerfLog.info("Imported manifest successfully provider_id: \(manifest.id), provider_name: \(manifest.name), source: \(sourceURL.absoluteString)")
        return manifest
    }

    public func importManifest(from string: String) async throws -> ProviderManifest {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw SDKError.manifestDeserializationError(details: "Invalid manifest URL")
        }

        return try await importManifest(from: url)
    }

    public func isEnabled(_ providerID: String) -> Bool {
        enabledProviderIDs.contains(providerID)
    }

    public func setEnabled(_ isEnabled: Bool, for providerID: String) {
        if isEnabled {
            enabledProviderIDs.insert(providerID)
        } else {
            enabledProviderIDs.remove(providerID)
        }
        Self.saveEnabledProviderIDs(enabledProviderIDs)

        Task {
            guard let providerSDK = Plugins.sharedProviderSDK() else { return }
            if isEnabled {
                if let manifest = manifests.first(where: { $0.id == providerID }) {
                    do {
                        await providerSDK.unregisterProvider(providerID)
                        try await providerSDK.registerManifest(manifest)
                        PerfLog.info("Dynamically registered manifest provider_id: \(providerID)")
                    } catch {
                        PerfLog.error("Failed to dynamically register manifest provider_id: \(providerID), error: \(error.localizedDescription)")
                    }
                }
            } else {
                await providerSDK.unregisterProvider(providerID)
                PerfLog.info("Dynamically unregistered manifest provider_id: \(providerID)")
            }
        }
    }

    public func removeProvider(_ providerID: String) async {
        enabledProviderIDs.remove(providerID)
        Self.saveEnabledProviderIDs(enabledProviderIDs)
        manifests.removeAll { $0.id == providerID }
        try? persist()
        guard let providerSDK = Plugins.sharedProviderSDK() else { return }
        await providerSDK.unregisterProvider(providerID)
        lastStatusMessage = "Removed \(providerID)"
        PerfLog.info("Removed provider manifest provider_id: \(providerID)")
    }

    public func reconcilePersistedManifests() async {
        if didReconcile { return }
        didReconcile = true

        PerfLog.info("Reconciling persisted manifests count: \(String(manifests.count))")
        guard let providerSDK = Plugins.sharedProviderSDK() else {
            lastStatusMessage = "Saved manifests will load when ProviderSDK is ready."
            PerfLog.warning("ProviderSDK unavailable while reconciling manifests")
            return
        }

        // First: unregister any previously-enabled manifests that are now disabled
        for manifest in manifests where !enabledProviderIDs.contains(manifest.id) {
            PerfLog.debug("Unregistering disabled manifest provider_id: \(manifest.id)")
            await providerSDK.unregisterProvider(manifest.id)
        }

        // Then: re-register all enabled manifests
        var restoredCount = 0
        for manifest in manifests where enabledProviderIDs.contains(manifest.id) {
            do {
                PerfLog.debug("Restoring manifest provider_id: \(manifest.id), provider_name: \(manifest.name)")
                await providerSDK.unregisterProvider(manifest.id)
                try await providerSDK.registerManifest(manifest)
                restoredCount += 1
                PerfLog.info("Restored manifest provider_id: \(manifest.id), provider_name: \(manifest.name)")
            } catch {
                lastErrorMessage = "Failed to restore \(manifest.name): \(error.localizedDescription)"
                PerfLog.error("Failed to restore manifest provider_id: \(manifest.id), provider_name: \(manifest.name), error: \(error.localizedDescription)")
            }
        }

        lastStatusMessage = manifests.isEmpty ? "No saved manifests to restore." : "Restored \(restoredCount) manifests."
    }

    public func cisumImportURL(for url: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "cisum"
        components.host = "manifest"
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        return components.url
    }

    public func setStatusMessage(_ message: String?) {
        lastStatusMessage = message
        if let message {
            PerfLog.info("Manifest store status updated message: \(message)")
        }
    }

    public func setErrorMessage(_ message: String?) {
        lastErrorMessage = message
        if let message {
            PerfLog.error("Manifest store error updated message: \(message)")
        }
    }

    private func upsert(_ manifest: ProviderManifest) throws {
        PerfLog.debug("Upserting manifest provider_id: \(manifest.id), provider_name: \(manifest.name)")
        manifests.removeAll { $0.id == manifest.id }
        manifests.insert(manifest, at: 0)
        try persist()
    }

    private func persist() throws {
        let storageURL = storageURL
        PerfLog.debug("Persisting manifests count: \(String(manifests.count)), storage_path: \(storageURL.path)")
        try fileManager.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let data = try encoder.encode(manifests)
        try data.write(to: storageURL, options: [.atomic])
        PerfLog.info("Persisted manifests count: \(String(manifests.count)), storage_path: \(storageURL.path), byte_count: \(String(data.count))")
    }

    private func register(_ manifest: ProviderManifest) async throws {
        guard let providerSDK = Plugins.sharedProviderSDK() else {
            lastStatusMessage = "Saved \(manifest.name); it will register when ProviderSDK is ready."
            PerfLog.warning("ProviderSDK unavailable during manifest registration provider_id: \(manifest.id), provider_name: \(manifest.name)")
            return
        }

        PerfLog.debug("Registering manifest with ProviderSDK provider_id: \(manifest.id), provider_name: \(manifest.name)")
        await providerSDK.unregisterProvider(manifest.id)
        try await providerSDK.registerManifest(manifest)
        PerfLog.info("Manifest registered with ProviderSDK provider_id: \(manifest.id), provider_name: \(manifest.name)")
    }

    private func loadRemoteData(from url: URL) async throws -> Data {
        if url.isFileURL {
            let data = try await URLSession.shared.data(from: url).0
            PerfLog.debug("Loaded local manifest file url: \(url.absoluteString), byte_count: \(String(data.count))")
            return data
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        PerfLog.debug("Fetching remote manifest url: \(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            PerfLog.error("Manifest request failed url: \(url.absoluteString), status_code: \(String(statusCode))")
            throw SDKError.manifestDeserializationError(details: "Manifest request failed for \(url.absoluteString)")
        }

        PerfLog.debug("Fetched remote manifest url: \(url.absoluteString), status_code: \(String(httpResponse.statusCode)), byte_count: \(String(data.count))")

        return data
    }

    private func resolvedSourceURL(for url: URL) throws -> URL {
        guard url.scheme == "cisum" else {
            return url
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let nestedURLString = components?.queryItems?.first(where: { $0.name == "url" || $0.name == "source" })?.value
            ?? components?.queryItems?.first(where: { $0.name == "manifest" })?.value

        guard let nestedURLString, let nestedURL = URL(string: nestedURLString) else {
            PerfLog.warning("Failed to resolve cisum import URL: \(url.absoluteString)")
            throw SDKError.manifestDeserializationError(details: "cisum URL is missing a manifest URL")
        }

        PerfLog.debug("Resolved cisum import URL: \(url.absoluteString), resolved_url: \(nestedURL.absoluteString)")
        return nestedURL
    }

    private static let enabledProvidersKey = "plugins.enabled_providers"

    private static func loadEnabledProviderIDs() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: enabledProvidersKey),
              let ids = try? JSONDecoder().decode(Set<String>.self, from: data)
        else {
            return []
        }
        return ids
    }

    private static func saveEnabledProviderIDs(_ ids: Set<String>) {
        guard let data = try? JSONEncoder().encode(ids) else { return }
        UserDefaults.standard.set(data, forKey: enabledProvidersKey)
    }

    private static func loadManifests(from fileManager: FileManager, decoder: JSONDecoder) async throws -> [ProviderManifest] {
        let storageURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let manifestsURL = storageURL
            .appendingPathComponent(Constants.folderName, isDirectory: true)
            .appendingPathComponent(Constants.fileName)

        guard fileManager.fileExists(atPath: manifestsURL.path) else {
            PerfLog.debug("No persisted manifests found storage_path: \(manifestsURL.path)")
            return []
        }

        let data = try await URLSession.shared.data(from: manifestsURL).0
        PerfLog.debug("Decoding persisted manifests storage_path: \(manifestsURL.path), byte_count: \(String(data.count))")
        return try decoder.decode([ProviderManifest].self, from: data)
    }
}
