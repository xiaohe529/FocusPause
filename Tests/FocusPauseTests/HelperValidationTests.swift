import Testing
@testable import FocusPauseHelperShared

struct HelperValidationTests {
    @Test
    func serviceNameValidation() {
        #expect(HelperValidation.serviceNameIsValid("Wi-Fi"))
        #expect(!HelperValidation.serviceNameIsValid(""))
        #expect(!HelperValidation.serviceNameIsValid("-Wi-Fi"))
        #expect(!HelperValidation.serviceNameIsValid("Wi\nFi"))
        #expect(!HelperValidation.serviceNameIsValid("Wi\u{200B}Fi"))
        #expect(!HelperValidation.serviceNameIsValid(String(repeating: "a", count: 257)))
    }

    @Test
    func dnsServerValidation() {
        #expect(HelperValidation.serverValueIsValid("Empty"))
        #expect(HelperValidation.serverValueIsValid("192.168.1.1"))
        #expect(HelperValidation.serverValueIsValid("2001:db8::1"))
        #expect(!HelperValidation.serverValueIsValid(" 8.8.8.8"))
        #expect(!HelperValidation.serverValueIsValid("dns.example.com"))
        #expect(!HelperValidation.serverValueIsValid("8.8.8.8\n8.8.4.4"))
        #expect(!HelperValidation.serverValueIsValid(""))
        #expect(!HelperValidation.serverListIsValid([]))
        #expect(!HelperValidation.serverListIsValid(["8.8.8.8", "bad"]))
        #expect(HelperValidation.serverListIsValid(["8.8.8.8", "1.1.1.1"]))
    }

    @Test
    func makeHostsContentReplacesManagedSectionAndDeduplicatesDomains() throws {
        let existing = """
        # Existing system entries
        127.0.0.1 local-service
        # FocusPause BEGIN
        127.0.0.1 old.example.com
        # FocusPause END
        # Other tail entry

        """
        let result = try #require(HelperValidation.makeHostsContent(
            existing: existing,
            domains: ["example.com", "Example.com", "another.example"]
        ))

        #expect(result.contains("127.0.0.1 local-service"))
        #expect(result.contains("# Other tail entry"))
        #expect(!result.contains("old.example.com"))
        #expect(result.components(separatedBy: "127.0.0.1 example.com").count - 1 == 1)
        #expect(result.components(separatedBy: "127.0.0.1 www.example.com").count - 1 == 1)
        #expect(result.components(separatedBy: "::1 example.com").count - 1 == 1)
        #expect(result.hasSuffix("# FocusPause END"))
    }

    @Test
    func makeHostsContentRejectsInvalidAndEmptyDomains() {
        #expect(HelperValidation.makeHostsContent(existing: "", domains: []) == nil)
        #expect(HelperValidation.makeHostsContent(existing: "", domains: ["bad domain"]) == nil)
    }

    @Test
    func removeFocusPauseSectionsPreservesOtherLines() {
        let content = """
        first
        # FocusPause BEGIN
        managed
        # FocusPause END
        last

        """
        #expect(HelperValidation.removeFocusPauseSections(from: content) == ["first", "last"])
    }

    @Test
    func removeFocusPauseSectionsRemovesUnterminatedSection() {
        #expect(
            HelperValidation.removeFocusPauseSections(from: "first\n# FocusPause BEGIN\nmanaged\nlast\n")
                == ["first"]
        )
    }
}
