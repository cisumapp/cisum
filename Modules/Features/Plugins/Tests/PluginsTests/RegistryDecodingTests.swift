//
//  RegistryDecodingTests.swift
//  PluginsTests
//
//  Fixtures are the real shapes served by https://8spine-modules.vercel.app/index.json
//

import Foundation
import Testing

@testable import Plugins

@Suite("Registry index decoding")
struct RegistryDecodingTests {
    private let base = URL(string: "https://8spine-modules.vercel.app/")!

    /// The two entry variants differ in `download` (relative vs absolute) and in how they tag
    /// (`tags` vs `labels`). Both have to land in the same type.
    @Test("a locally-hosted entry resolves its relative download path")
    func localEntry() throws {
        let json = """
        {
          "category:modules": [{
            "id": "tidals-morgk",
            "name": "ASH BABY",
            "file": "tridalModule.8spine",
            "download": "modules/tridalModule.8spine",
            "version": "v3.8.3",
            "code": 383,
            "type": "MODULE",
            "author": "morgk",
            "description": "A module.",
            "tags": ["MAYBE FAST", "HI-RES", "LOSSLESS"],
            "featured": false,
            "trusted": false,
            "nsfw": false,
            "size": 28548,
            "folder": "modules"
          }]
        }
        """

        let (entries, externals) = RegistryDecoder.decode(Data(json.utf8), base: base)

        #expect(externals.isEmpty)
        let entry = try #require(entries.first)
        #expect(entry.id == "tidals-morgk")
        #expect(entry.name == "ASH BABY")
        #expect(entry.versionCode == 383)
        #expect(entry.size == 28548)
        #expect(entry.category == "modules")
        #expect(entry.labels == ["MAYBE FAST", "HI-RES", "LOSSLESS"])
        #expect(entry.downloadURL.absoluteString == "https://8spine-modules.vercel.app/modules/tridalModule.8spine")
    }

    @Test("a federated entry keeps its absolute download URL and reads `labels`")
    func externalEntry() throws {
        let json = """
        {
          "category:livie_modules": [{
            "id": "liver",
            "name": "Liver",
            "author": "Livie",
            "version": "3.2.0",
            "labels": ["MP3", "FLAC", "LOSSLESS", "MULTI-SOURCE"],
            "trusted": true,
            "featured": true,
            "download": "https://raw.githubusercontent.com/lvwmwm/8spine/main/liver_module.js",
            "type": "MODULE"
          }]
        }
        """

        let (entries, _) = RegistryDecoder.decode(Data(json.utf8), base: base)

        let entry = try #require(entries.first)
        #expect(entry.downloadURL.absoluteString == "https://raw.githubusercontent.com/lvwmwm/8spine/main/liver_module.js")
        #expect(entry.labels.contains("LOSSLESS"))
        #expect(entry.isTrusted)
        #expect(entry.category == "livie_modules")
    }

    @Test("external_sources are surfaced for federation")
    func externalSources() throws {
        let json = """
        {
          "external_sources": [
            {
              "key": "ricky_modules",
              "title": "RICKY Modules",
              "url": "https://monochrome.rickyaddons.dpdns.org/8spine-source.json",
              "baseUrl": "https://monochrome.rickyaddons.dpdns.org"
            }
          ]
        }
        """

        let (_, externals) = RegistryDecoder.decode(Data(json.utf8), base: base)

        let source = try #require(externals.first)
        #expect(source.key == "ricky_modules")
        #expect(source.title == "RICKY Modules")
        #expect(source.baseURL?.absoluteString == "https://monochrome.rickyaddons.dpdns.org")
    }

    @Test("an entry with no id or no download is skipped, not fatal")
    func malformedEntriesSkipped() {
        let json = """
        {
          "category:modules": [
            { "name": "no id" },
            { "id": "no-download" },
            { "id": "good", "download": "modules/a.js" }
          ]
        }
        """

        let (entries, _) = RegistryDecoder.decode(Data(json.utf8), base: base)
        #expect(entries.count == 1)
        #expect(entries.first?.id == "good")
    }

    @Test("garbage input yields an empty catalog rather than throwing")
    func garbageInput() {
        let (entries, externals) = RegistryDecoder.decode(Data("not json".utf8), base: base)
        #expect(entries.isEmpty)
        #expect(externals.isEmpty)
    }
}

@Suite("Plugin storage")
struct PluginStorageTests {
    private func temporaryStorage() -> (PluginStorage, URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("plugin-store-tests-\(UUID().uuidString)")
        return (PluginStorage(directory: directory), directory)
    }

    @Test("a saved plugin round-trips with its source intact")
    func roundTrip() async throws {
        let (storage, directory) = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: directory) }

        let plugin = InstalledPlugin(
            id: "tidal", name: "TIDAL", version: "1.0.0",
            source: "return { id: 'tidal' };",
            settings: ["quality": "LOSSLESS"]
        )

        try await storage.save(plugin)
        let loaded = try await storage.loadAll()

        #expect(loaded.count == 1)
        #expect(loaded.first?.id == "tidal")
        #expect(loaded.first?.source == "return { id: 'tidal' };")
        #expect(loaded.first?.settings["quality"] == "LOSSLESS")
    }

    /// Plugin ids come from third-party registries, so an id containing path separators must not
    /// let a write escape the plugins directory.
    @Test("a hostile plugin id cannot write outside the plugins directory")
    func pathTraversalIsNeutralised() async throws {
        let (storage, directory) = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: directory) }

        let hostile = InstalledPlugin(
            id: "../../../etc/evil", name: "Evil", version: "1", source: "return { id: 'x' };"
        )
        try await storage.save(hostile)

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.contains { $0.hasSuffix(".module") })
        #expect(!FileManager.default.fileExists(atPath: "/etc/evil.module"))
    }

    @Test("deleting removes both the source file and the index entry")
    func deletion() async throws {
        let (storage, directory) = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: directory) }

        try await storage.save(InstalledPlugin(id: "a", name: "A", version: "1", source: "return { id: 'a' };"))
        try await storage.save(InstalledPlugin(id: "b", name: "B", version: "1", source: "return { id: 'b' };"))
        try await storage.delete("a")

        let loaded = try await storage.loadAll()
        #expect(loaded.map(\.id) == ["b"])
    }

    /// A plugin whose source file vanished would otherwise fail confusingly at load time.
    @Test("an index entry with a missing source file is dropped")
    func missingSourceFileDropped() async throws {
        let (storage, directory) = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: directory) }

        try await storage.save(InstalledPlugin(id: "gone", name: "Gone", version: "1", source: "return { id: 'gone' };"))
        try FileManager.default.removeItem(at: directory.appendingPathComponent("gone.module"))

        #expect(try await storage.loadAll().isEmpty)
    }
}
