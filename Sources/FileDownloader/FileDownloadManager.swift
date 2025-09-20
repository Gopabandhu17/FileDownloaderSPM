import Foundation

public protocol FileDownloading {
    func download(
        from url: URL,
        options: DownloadOptions,
        onProgress: @escaping ((Double) -> Void),
        onCompletion: @escaping ((Result<URL, Error>) -> Void)
    )
}

public final class FileDownloadManager: NSObject, FileDownloading {
    
    public static let shared = FileDownloadManager()
    
    private var onProgress: ((Double) -> Void)?
    private var onCompletion: ((Result<URL, Error>) -> Void)?
    private var options: DownloadOptions?
    private var response: URLResponse?
    
    private var session: URLSession?
    private var downloadTask: URLSessionDownloadTask?
    
    // private(set) var resumeData: Data?
    
    private override init() {}
    
    public func download(
        from url: URL,
        options: DownloadOptions,
        onProgress: @escaping ((Double) -> Void),
        onCompletion: @escaping ((Result<URL, Error>) -> Void)
    ) {
        
        self.onProgress = onProgress
        self.onCompletion = onCompletion
        self.options = options
        
        // Build Request
        var request = URLRequest(url: url)
        if let timeout = options.timeout {
            request.timeoutInterval = timeout
        }
        for (key, value) in options.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        self.downloadTask = session.downloadTask(with: request)
        self.downloadTask?.resume()
        
    }
}

// MARK: - URLSessionDownloadDelegate -
extension FileDownloadManager: URLSessionDownloadDelegate, @unchecked Sendable {
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let options else {
            onCompletion?(.failure(NetworkError.invalidResponse))
            return
        }
        
        // TODO: - Some servers are returning only url of file, so once you get the file location no need to validate it, will find some alternative way to validate the response which will suits all the edge cases
        /*
        // Validate response
        guard let http = response as? HTTPURLResponse else {
            onCompletion?(.failure(NetworkError.invalidResponse))
            return
        }
        guard (200...299).contains(http.statusCode) else {
            onCompletion?(.failure(NetworkError.badHTTPStatus(http.statusCode)))
            return
        }
         */
        
        // Decide filename
        let filename = options.filename ?? UUID().uuidString
        
        // Build destination URL
        let destinationDirectory = options.destinationDirectory
        do {
            try ensureDirectoryExists(destinationDirectory)
        } catch {
            onCompletion?(.failure(error))
            return
        }
        let destinationURL = destinationDirectory.appendingPathComponent(filename)
        
        // Handle overwrite
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            if options.overwrite {
                try? fileManager.removeItem(at: destinationURL)
            } else {
                // If not overwriting, pickup a unique filename
                let uniqueURL = makeUniqueURL(for: destinationURL)
                return moveDownloadFile(from: location, to: uniqueURL)
            }
        }
        
        moveDownloadFile(from: location, to: destinationURL)
    }
    
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress?(progress)
    }
}

// MARK: - Disk Helpers -
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
    
    private func moveDownloadFile(from tempURL: URL, to destinationURL: URL) {
        let fileManager = FileManager.default
        do {
            // Move is atomic and avoid full copy when possible.
            try fileManager.moveItem(at: tempURL, to: destinationURL)
            onCompletion?(.success(destinationURL))
        } catch {
            // Fallback : Copy then remove, in case move failed.
            do {
                try fileManager.copyItem(at: tempURL, to: destinationURL)
                try? fileManager.removeItem(at: tempURL)
                onCompletion?(.success(destinationURL))
            } catch {
                onCompletion?(.failure(NetworkError.fileMoveFailed(underlying: error)))
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

// MARK: - Task Helpers -
extension FileDownloadManager {
//    public func pause() {
//        downloadTask?.cancel { [weak self] resumeData in
//            guard let self else { return }
//            self.resumeData = resumeData
//            onCompletion?(.failure(NetworkError.paused))
//        }
//    }
    
//    public func resume() {
//        guard let resumeData else { return }
//        downloadTask = session?.downloadTask(withResumeData: resumeData, completionHandler: { url, urlResponse, error in
//            guard let url, error == nil else {
//                self.onCompletion?(.failure(NetworkError.invalidResponse))
//                return
//            }
//            self.onCompletion?(.success(url))
//        })
//    }
    
    public func cancel() {
        downloadTask?.cancel()
        onCompletion?(.failure(NetworkError.cancelled))
    }
}
