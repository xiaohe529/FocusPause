import Foundation
import Testing
@testable import FocusPause

struct HelperInstallerStagingTests {
    @Test
    func stagingUsesUniqueSecurePrivateDirectory() throws {
        let first = try HelperInstaller.stageHelperFiles(token: "token-1", plistData: Data("plist-1".utf8))
        let second = try HelperInstaller.stageHelperFiles(token: "token-2", plistData: Data("plist-2".utf8))
        defer {
            first.cleanup()
            second.cleanup()
        }

        #expect(first.directory != second.directory)
        #expect(try FileManager.default.attributesOfItem(atPath: first.directory.path)[.posixPermissions] as? NSNumber == 0o700)
        #expect(try FileManager.default.attributesOfItem(atPath: first.tokenURL.path)[.posixPermissions] as? NSNumber == 0o600)
        #expect(try String(contentsOf: first.tokenURL, encoding: .utf8) == "token-1")
        #expect(try Data(contentsOf: first.plistURL) == Data("plist-1".utf8))
    }

    @Test
    func stagingCleanupRemovesTemporaryDirectory() throws {
        let staging = try HelperInstaller.stageHelperFiles(token: "token", plistData: Data("plist".utf8))
        staging.cleanup()
        #expect(!FileManager.default.fileExists(atPath: staging.directory.path))
    }
}
