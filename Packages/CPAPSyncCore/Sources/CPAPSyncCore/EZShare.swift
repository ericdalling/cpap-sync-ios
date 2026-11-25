import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum CardError: Error, LocalizedError {
    case invalidLink, invalidListing, badResponse, limitExceeded, unsafePath, unsupportedContent, httpStatus(Int)
    public var errorDescription: String? {
        switch self {
        case .invalidLink: return "Card returned an unsupported or unsafe link."
        case .invalidListing: return "Card did not return a recognizable directory listing."
        case .badResponse: return "Card HTTP request failed. Check Wi-Fi and local network permission."
        case .httpStatus(let status): return "Card returned HTTP \(status)."
        case .limitExceeded: return "Safety limit reached; sync stopped."
        case .unsafePath: return "Unsafe local path; sync stopped."
        case .unsupportedContent: return "Card returned HTML instead of a file."
        }
    }
}

public struct CardStamp: Equatable, Sendable {
    public let signature: String
    public let modifiedAt: Date
    public init(signature: String, modifiedAt: Date) {
        self.signature = signature
        self.modifiedAt = modifiedAt
    }
}

public struct CardEntry: Equatable, Sendable {
    public let name: String
    public let url: URL
    public let isDirectory: Bool
    public let stamp: CardStamp?
    public init(name: String, url: URL, isDirectory: Bool, stamp: CardStamp? = nil) {
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.stamp = stamp
    }
}

public protocol CardTransport: Sendable {
    func get(_ url: URL) async throws -> Data
}

public struct CardAddress: Sendable {
    public static let host = "192.168.4.1"
    public static let root = URL(string: "http://192.168.4.1/dir?dir=A:")!
    public static func valid(_ url: URL, directory: Bool? = nil) -> Bool {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: true),
              c.scheme == "http", c.host == host, c.port == nil || c.port == 80,
              c.user == nil, c.password == nil, c.fragment == nil,
              let query = c.query, !query.isEmpty else { return false }
        if let directory { return c.path == (directory ? "/dir" : "/download") }
        return c.path == "/dir" || c.path == "/download"
    }
    public static func safeName(_ s: String) -> Bool {
        !s.isEmpty && s != "." && s != ".." && !s.contains("/") &&
        !s.contains("\\") && !s.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}

private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public final class LocalCardTransport: CardTransport, @unchecked Sendable {
    private let session: URLSession
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 120
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.allowsCellularAccess = false
        session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    public func get(_ url: URL) async throws -> Data {
        guard CardAddress.valid(url) else { throw CardError.invalidLink }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.url == url else { throw CardError.badResponse }
        guard http.statusCode == 200 else { throw CardError.httpStatus(http.statusCode) }
        if url.path == "/download",
           http.mimeType?.lowercased() == "text/html" { throw CardError.unsupportedContent }
        return data
    }
}

public enum DirectoryParser {
    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            (0..<match.numberOfRanges).map { i in
                let range = match.range(at: i)
                return range.location == NSNotFound ? "" : ns.substring(with: range)
            }
        }
    }
    private static func decode(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        for match in matches("&#(x[0-9A-Fa-f]+|[0-9]+);", in: result) {
            let token = match[1]
            let number = token.hasPrefix("x") ? UInt32(token.dropFirst(), radix: 16) : UInt32(token)
            if let number, let scalar = UnicodeScalar(number) {
                result = result.replacingOccurrences(of: match[0], with: String(scalar))
            }
        }
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }
    // Read optional firmware timestamp and rounded size before a file link.
    // Unparseable or absent metadata always results in a download, never a skip.
    private static func stamp(in prefix: String) -> CardStamp? {
        let pattern = #"(?m)(\d{4})-\s*(\d{1,2})-\s*(\d{1,2})\s+(\d{1,2}):\s*(\d{1,2}):\s*(\d{1,2})\s+(\d+(?:\.\d+)?(?:KB|MB|GB|B)?)\s*$"#
        guard let groups = matches(pattern, in: prefix).last, groups.count == 8 else { return nil }
        let parts = groups[1...6].compactMap { Int($0) }
        guard parts.count == 6 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let fields = DateComponents(timeZone: calendar.timeZone, year: parts[0],
                                    month: parts[1], day: parts[2], hour: parts[3],
                                    minute: parts[4], second: parts[5])
        guard let date = calendar.date(from: fields) else { return nil }
        let result = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard result.year == parts[0], result.month == parts[1], result.day == parts[2],
              result.hour == parts[3], result.minute == parts[4], result.second == parts[5] else { return nil }
        return CardStamp(signature: parts.map(String.init).joined(separator: "-") + "|" + groups[7].uppercased(),
                         modifiedAt: date)
    }
    public static func parse(_ html: String, relativeTo directory: URL) throws -> [CardEntry] {
        guard CardAddress.valid(directory, directory: true), html.utf8.count <= 8_000_000 else {
            throw CardError.invalidListing
        }
        let blocks = matches("(?is)<pre\\b[^>]*>(.*?)</pre\\s*>", in: html)
        guard blocks.count == 1 else { throw CardError.invalidListing }
        let anchors = matches("(?is)<a\\b[^>]*\\bhref\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))[^>]*>(.*?)</a\\s*>", in: blocks[0][1])
        var entries: [CardEntry] = []
        var names = Set<String>()
        let listing = blocks[0][1] as NSString
        var cursor = 0
        for a in anchors {
            let range = listing.range(of: a[0], range: NSRange(location: cursor, length: listing.length - cursor))
            guard range.location != NSNotFound else { throw CardError.invalidListing }
            let prefix = listing.substring(with: NSRange(location: cursor, length: range.location - cursor))
            cursor = NSMaxRange(range)
            let name = decode(a[4].replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)).trimmingCharacters(in: .whitespacesAndNewlines)
            if name == "." || name == ".." || name == "[..]" || name.lowercased() == "parent directory" { continue }
            let href = decode([a[1], a[2], a[3]].first(where: { !$0.isEmpty }) ?? "")
            guard let url = URL(string: href, relativeTo: directory)?.absoluteURL,
                  CardAddress.valid(url), CardAddress.safeName(name) else { throw CardError.invalidLink }
            guard names.insert(name.precomposedStringWithCanonicalMapping.lowercased()).inserted else { throw CardError.invalidListing }
            entries.append(CardEntry(name: name, url: url, isDirectory: url.path == "/dir",
                                     stamp: url.path == "/dir" ? nil : stamp(in: prefix)))
        }
        // Do not interpret a malformed link-bearing response as an empty directory.
        let openingCount = matches("(?is)<a\\b", in: blocks[0][1]).count
        guard openingCount == anchors.count else { throw CardError.invalidListing }
        return entries
    }
}

public struct EZShareClient: Sendable {
    private let transport: any CardTransport
    public init(transport: any CardTransport = LocalCardTransport()) { self.transport = transport }
    private func request(_ url: URL) async throws -> Data {
        for attempt in 0..<3 {
            try Task.checkCancellation()
            do { return try await transport.get(url) }
            catch is CancellationError { throw CancellationError() }
            catch {
                let retryable: Bool
                if let network = error as? URLError {
                    retryable = [.timedOut, .networkConnectionLost, .cannotConnectToHost,
                                 .notConnectedToInternet].contains(network.code)
                } else if case CardError.httpStatus(let status) = error {
                    retryable = status == 429 || (500...599).contains(status)
                } else {
                    retryable = false
                }
                guard retryable && attempt < 2 else { throw error }
                try await Task.sleep(nanoseconds: UInt64(250 * (1 << attempt)) * 1_000_000)
            }
        }
        throw CardError.badResponse
    }
    public func list(_ directory: URL = CardAddress.root) async throws -> [CardEntry] {
        guard CardAddress.valid(directory, directory: true) else { throw CardError.invalidLink }
        let data = try await request(directory)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw CardError.invalidListing
        }
        return try DirectoryParser.parse(text, relativeTo: directory)
    }
    public func download(_ entry: CardEntry) async throws -> Data {
        guard !entry.isDirectory, CardAddress.valid(entry.url, directory: false) else { throw CardError.invalidLink }
        return try await request(entry.url)
    }
}
