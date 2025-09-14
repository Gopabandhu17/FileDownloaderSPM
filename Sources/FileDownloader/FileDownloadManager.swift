import Foundation

public protocol FileDownloading {
    func download(form url: URL,
                  options: DownloadOptions,
                  onProgress: ((Double) -> Void)?) async throws -> URL
}

public final class FileDownloadManager: FileDownloading {
    
    private var session: URLSession = .shared
    private var delegate: DownloadProgressDelegate?
    
//    public init(session: URLSession = .shared) {
//        self.session = session
//    }
    
    public func download(form url: URL, options: DownloadOptions, onProgress: ((Double) -> Void)?) async throws -> URL {
        
        // Build Request
        var request = URLRequest(url: url)
        if let timeout = options.timeout {
            request.timeoutInterval = timeout
        }
        for (key, value) in options.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Delegate for progress
        self.delegate = onProgress != nil ? DownloadProgressDelegate(onProgress: onProgress) : nil
        self.session = URLSession(configuration: .default, delegate: self.delegate, delegateQueue: nil)
        
        // Perform download
        let (tempURL, response): (URL, URLResponse)
        do {
            (tempURL, response) = try await session.download(for: request, delegate: delegate)
        } catch is CancellationError {
            throw NetworkError.cancelled
        } catch {
            throw error
        }
        
        // Validate response
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw NetworkError.badHTTPStatus(http.statusCode)
        }
        
        // Decide filename
        let filename = options.filename ?? UUID().uuidString
        
        // Build destination URL
        let destinationDirectory = options.destinationDirectory
        try ensureDirectoryExists(destinationDirectory)
        let destinationURL = destinationDirectory.appendingPathComponent(filename)
        
        // Handle overwrite
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            if options.overwrite {
                try? fileManager.removeItem(at: destinationURL)
            } else {
                // If not overwriting, pickup a unique filename
                let uniqueURL = makeUniqueURL(for: destinationURL)
                return try moveDownloadFile(from: tempURL, to: uniqueURL)
            }
        }
        
        return try moveDownloadFile(from: tempURL, to: destinationURL)
    }
}

// MARK: - Helpers -
extension FileDownloadManager {
    
    private func ensureDirectoryExists(_ url: URL) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path()) {
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                throw NetworkError.directoryCreationFailed(underlying: error)
            }
        }
    }
    
    private func moveDownloadFile(from tempURL: URL, to destinationURL: URL) throws -> URL {
        let fileManager = FileManager.default
        do {
            // Move is atomic and avoid full copy when possible.
            try fileManager.moveItem(at: tempURL, to: destinationURL)
            return destinationURL
        } catch {
            // Fallback : Copy then remove, in case move failed.
            do {
                try fileManager.copyItem(at: tempURL, to: destinationURL)
                try? fileManager.removeItem(at: tempURL)
                return destinationURL
            } catch {
                throw NetworkError.fileMoveFailed(underlying: error)
            }
        }
    }
    
    private func makeUniqueURL(for url: URL) -> URL {
        let fileManager = FileManager.default
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent()
        
        var candidate = url
        var index = 1
        
        while fileManager.fileExists(atPath: candidate.path()) {
            let newName = ext.isEmpty ? "\(base)\(index)" : "\(base)\(index).\(ext)"
            candidate = dir.appendingPathComponent(newName)
            index += 1
        }
        return candidate
    }
}
