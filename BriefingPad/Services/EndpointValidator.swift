import Foundation

enum EndpointValidator {
    enum ValidationError: Error, LocalizedError {
        case invalidURL
        case unsupportedScheme(String)
        case userinfoProhibited
        case insecureExternalHTTP
        case blockedIP(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return NSLocalizedString("endpoint.error.invalidURL", comment: "")
            case .unsupportedScheme(let scheme):
                return String(format: NSLocalizedString("endpoint.error.unsupportedScheme", comment: ""), scheme)
            case .userinfoProhibited:
                return NSLocalizedString("endpoint.error.userinfoProhibited", comment: "")
            case .insecureExternalHTTP:
                return NSLocalizedString("endpoint.error.insecureExternalHTTP", comment: "")
            case .blockedIP(let ip):
                return String(format: NSLocalizedString("endpoint.error.blockedIP", comment: ""), ip)
            }
        }
    }

    /// Validates the endpoint URL string according to the security policy.
    /// Returns a normalized URL (without trailing slash) if valid.
    static func validate(urlString: String) throws -> URL {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host else {
            throw ValidationError.invalidURL
        }

        // Block userinfo
        if components.user != nil || components.password != nil {
            throw ValidationError.userinfoProhibited
        }

        if scheme == "https" {
            // HTTPS allows any host
            return try assembleNormalizedURL(components)
        } else if scheme == "http" {
            if isAllowedLocalOrPrivate(host: host) {
                return try assembleNormalizedURL(components)
            } else {
                throw ValidationError.insecureExternalHTTP
            }
        } else {
            throw ValidationError.unsupportedScheme(scheme)
        }
    }

    private static func assembleNormalizedURL(_ components: URLComponents) throws -> URL {
        var comps = components
        // Normalize trailing slash
        if comps.path.hasSuffix("/") {
            comps.path = String(comps.path.dropLast())
        }
        guard let url = comps.url else {
            throw ValidationError.invalidURL
        }
        return url
    }

    private static func isAllowedLocalOrPrivate(host: String) -> Bool {
        let lowerHost = host.lowercased()

        // localhost
        if lowerHost == "localhost" {
            return true
        }

        // *.local
        if lowerHost.hasSuffix(".local") {
            return true
        }

        // Clean host for IP checks (remove brackets for IPv6)
        let cleanHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))

        // IPv6 loopback
        if cleanHost == "::1" {
            return true
        }

        // IPv4 ranges
        if let ipv4 = parseIPv4(cleanHost) {
            // Block 0.0.0.0
            if ipv4 == 0 { return false }

            // Block Multicast (224.0.0.0/4)
            if (ipv4 & 0xF0000000) == 0xE0000000 { return false }

            // Block Broadcast
            if ipv4 == 0xFFFFFFFF { return false }

            // 127.0.0.0/8 (Loopback)
            if matchCIDR(ipv4: ipv4, network: "127.0.0.0", mask: 8) { return true }
            // 10.0.0.0/8 (Private)
            if matchCIDR(ipv4: ipv4, network: "10.0.0.0", mask: 8) { return true }
            // 172.16.0.0/12 (Private)
            if matchCIDR(ipv4: ipv4, network: "172.16.0.0", mask: 12) { return true }
            // 192.168.0.0/16 (Private)
            if matchCIDR(ipv4: ipv4, network: "192.168.0.0", mask: 16) { return true }
            // 100.64.0.0/10 (Carrier-grade NAT)
            if matchCIDR(ipv4: ipv4, network: "100.64.0.0", mask: 10) { return true }
        }

        return false
    }

    private static func parseIPv4(_ host: String) -> UInt32? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var result: UInt32 = 0
        for part in parts {
            guard let val = UInt32(part), val <= 255 else { return nil }
            result = (result << 8) | val
        }
        return result
    }

    private static func matchCIDR(ipv4: UInt32, network: String, mask: Int) -> Bool {
        guard let netAddr = parseIPv4(network) else { return false }
        let shift = 32 - mask
        let bitMask: UInt32 = shift == 32 ? 0 : (0xFFFFFFFF << shift)
        return (ipv4 & bitMask) == (netAddr & bitMask)
    }
}
