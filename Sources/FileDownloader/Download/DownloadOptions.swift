import Foundation

public struct DownloadOptions: Sendable {
    public var destinationDirectory: URL
    public var filename: String?
    public var overwrite: Bool
    public var headers: [String: String]
    public var timeout: TimeInterval?
    
    public init(
        destinationURL: URL,
        filename: String? = nil,
        overwrite: Bool = false,
        headers: [String : String] = [:],
        timeout: TimeInterval? = nil
    ) {
        self.destinationDirectory = destinationURL
        self.filename = filename
        self.overwrite = overwrite
        self.headers = headers
        self.timeout = timeout
    }
}
