import Foundation
import FocusPauseHelperShared

enum HelperInstaller {
    static func install() async -> Bool {
        guard let helperBinURL = bundledHelperBinaryURL else {
            FocusLogger.error("HelperInstaller: bundled helper binary not found")
            return false
        }

        let token = generateToken()

        guard let plistSrc = findPlist() else {
            FocusLogger.error("HelperInstaller: plist not found in bundle")
            return false
        }
        guard let plistData = try? Data(contentsOf: plistSrc) else {
            FocusLogger.error("HelperInstaller: failed to read plist data")
            return false
        }

        let staging: HelperStagingFiles
        do {
            staging = try stageHelperFiles(token: token, plistData: plistData)
        } catch {
            FocusLogger.error("HelperInstaller: failed to stage helper files: \(error)")
            return false
        }
        defer { staging.cleanup() }

        let binSrc = helperBinURL.path
        let ownerUID = getuid()
        let script = """
        set binDest to "/Library/PrivilegedHelperTools/com.focuspause.helper"
        set plistDest to "/Library/LaunchDaemons/com.focuspause.helper.plist"
        set tokenDest to "/Library/Application Support/FocusPause/helper.token"
        set binSrc to "\(binSrc)"
        set plistSrc to "\(staging.plistURL.path)"
        set tokenSrc to "\(staging.tokenURL.path)"

        do shell script "mkdir -p /Library/PrivilegedHelperTools /Library/Application\\\\ Support/FocusPause" with administrator privileges

        try
            do shell script "launchctl bootout system /Library/LaunchDaemons/com.focuspause.helper.plist 2>/dev/null || true" with administrator privileges
        end try

        do shell script "cp -f " & quoted form of binSrc & " " & quoted form of binDest & " && chmod 755 " & quoted form of binDest & " && chown root:wheel " & quoted form of binDest with administrator privileges

        do shell script "cp -f " & quoted form of plistSrc & " " & quoted form of plistDest & " && chmod 644 " & quoted form of plistDest & " && chown root:wheel " & quoted form of plistDest with administrator privileges

        do shell script "mkdir -p /Library/Application\\\\ Support/FocusPause && cp -f " & quoted form of tokenSrc & " " & quoted form of tokenDest & " && chmod 600 " & quoted form of tokenDest & " && chown \(ownerUID):wheel " & quoted form of tokenDest with administrator privileges

        do shell script "launchctl bootstrap system " & quoted form of plistDest with administrator privileges
        """

        return await runOSAScript(script)
    }

    static func uninstall() async -> Bool {
        let script = """
        do shell script "launchctl bootout system /Library/LaunchDaemons/com.focuspause.helper.plist 2>/dev/null || true" with administrator privileges
        do shell script "rm -f /Library/LaunchDaemons/com.focuspause.helper.plist /Library/PrivilegedHelperTools/com.focuspause.helper /Library/Application\\\\ Support/FocusPause/helper.token" with administrator privileges
        """
        return await runOSAScript(script)
    }

    static func isRunning() async -> Bool {
        await HelperConnection.shared.probe()
    }

    /// Older installs exposed the helper token to every local user. Treat those
    /// installations as needing repair so the next helper install fixes them.
    static func tokenPermissionsAreSecure() -> Bool {
        let path = HelperConstants.tokenPath
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let permissions = attributes[.posixPermissions] as? NSNumber,
              let owner = attributes[.ownerAccountName] as? String else {
            return false
        }
        return permissions.uint16Value == 0o600 && owner == NSUserName()
    }

    // MARK: - Internals

    private static var bundledHelperBinaryURL: URL? {
        // 1. In .app bundle: Contents/Helpers/com.focuspause.helper
        let helpersDir = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/com.focuspause.helper")
        if FileManager.default.fileExists(atPath: helpersDir.path) {
            return helpersDir
        }
        // 2. Dev mode: next to the executable (e.g., .build/arm64-apple-macosx/debug/)
        let exeDir = Bundle.main.bundleURL
            .appendingPathComponent("FocusPauseHelper")
        if FileManager.default.fileExists(atPath: exeDir.path) {
            return exeDir
        }
        // 3. Fallback: check if already installed at system path
        let installed = URL(fileURLWithPath: HelperConstants.installedBinPath)
        if FileManager.default.fileExists(atPath: installed.path) {
            return installed
        }
        return nil
    }

    private static func findPlist() -> URL? {
        // 1. In .app bundle: Contents/Resources/com.focuspause.helper.plist
        if let url = Bundle.main.url(forResource: "com.focuspause.helper", withExtension: "plist") {
            return url
        }
        // 2. Dev mode: next to the executable (build-app.sh copies it there)
        let devPlist = Bundle.main.bundleURL
            .appendingPathComponent("com.focuspause.helper.plist")
        if FileManager.default.fileExists(atPath: devPlist.path) {
            return devPlist
        }
        return nil
    }

    private static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        if status != errSecSuccess {
            for i in 0..<32 { bytes[i] = UInt8.random(in: 0...255) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func runOSAScript(_ appleScript: String) async -> Bool {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                proc.arguments = ["-e", appleScript]
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = pipe
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    if proc.terminationStatus == 0 {
                        cont.resume(returning: true)
                    } else {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let err = String(data: data, encoding: .utf8) ?? ""
                        FocusLogger.error("HelperInstaller osascript failed: \(err)")
                        cont.resume(returning: false)
                    }
                } catch {
                    FocusLogger.error("HelperInstaller spawn failed: \(error)")
                    cont.resume(returning: false)
                }
            }
        }
    }
}
/// A private, per-install staging directory. A fresh UUID prevents concurrent
/// installs from overwriting one another and avoids predictable /tmp filenames.
struct HelperStagingFiles {
    let directory: URL
    let tokenURL: URL
    let plistURL: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

extension HelperInstaller {
    static func stageHelperFiles(token: String, plistData: Data) throws -> HelperStagingFiles {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("FocusPauseHelperInstall-\(UUID().uuidString)", isDirectory: true)
        let tokenURL = directory.appendingPathComponent("helper.token", isDirectory: false)
        let plistURL = directory.appendingPathComponent("com.focuspause.helper.plist", isDirectory: false)
        let staging = HelperStagingFiles(directory: directory, tokenURL: tokenURL, plistURL: plistURL)

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

            try token.write(to: tokenURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)

            try plistData.write(to: plistURL)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: plistURL.path)
            return staging
        } catch {
            staging.cleanup()
            throw error
        }
    }
}
