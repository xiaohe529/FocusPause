import Testing
@testable import FocusPauseHelperShared

struct DomainNormalizerTests {
    @Test
    func normalizeAcceptsURLsAndHostnames() {
        #expect(DomainNormalizer.normalize("  EXAMPLE.COM \n") == "example.com")
        #expect(DomainNormalizer.normalize("https://Example.co.uk/path") == "example.co.uk")
        #expect(DomainNormalizer.normalize("http://example.com.") == "example.com")
        #expect(DomainNormalizer.normalize("sub-domain.example.io") == "sub-domain.example.io")
    }

    @Test
    func normalizeRejectsUnsafeOrMalformedInput() {
        let invalid = [
            "",
            "   ",
            "http://",
            "localhost",
            "example.com:8080",
            "exa mple.com",
            "example\n.com",
            "-example.com",
            "example-.com",
            ".example.com",
            String(repeating: "a", count: 254),
            "exa\u{200B}mple.com"
        ]

        for value in invalid {
            #expect(DomainNormalizer.normalize(value) == nil, "expected nil for \(value)")
        }
    }

    @Test
    func normalizeRejectsOverlongLabel() {
        #expect(DomainNormalizer.normalize("\(String(repeating: "a", count: 64)).com") == nil)
    }
}
