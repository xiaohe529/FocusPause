import Testing
@testable import FocusPause

struct UpdaterTests {
    @Test
    func versionNormalizationOnlyRemovesLeadingTag() {
        #expect(Updater.normalizedVersion(" v1.2.3 ") == "1.2.3")
        #expect(Updater.normalizedVersion("1v2") == "1v2")
        #expect(Updater.compareVersions("v1.2.0", "1.2.0") == .orderedSame)
    }

    @Test
    func versionComparisonSupportsDifferentLengths() {
        #expect(Updater.compareVersions("1.0.0", "1.0.0") == .orderedSame)
        #expect(Updater.compareVersions("1.0", "1.0.1") == .orderedAscending)
        #expect(Updater.compareVersions("1.2.0", "1.1.9") == .orderedDescending)
        #expect(Updater.compareVersions("", "0.0.1") == .orderedAscending)
    }
}
