import Foundation

public protocol FileDownloading {
    func download(form url: URL,
                  options: DownloadOptions,
                  onProgress: ((Double) -> Void)?) async throws -> URL
}

public final class FileDownloadManager: FileDownloading {
    
    private let session: URLSession
    
    public init(session: URLSession = .shared) {
        self.session = session
    }
    
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
        let delegate = onProgress != nil ? DownloadProgressDelegate(onProgress: onProgress) : nil
        
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
        let destinationURL = destinationDirectory.appendingPathComponent(filename)
        
        // Handle overwrite
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            if options.overwrite {
                try? fileManager.removeItem(at: destinationURL)
            } else {
                // TODO: create a unique URL and replace with destinationURL here
                return try moveDownloadFile(from: tempURL, to: destinationURL)
            }
        }
        
        return try moveDownloadFile(from: tempURL, to: destinationURL)
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
}
