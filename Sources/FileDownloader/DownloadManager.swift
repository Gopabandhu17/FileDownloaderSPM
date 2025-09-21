import Foundation

public final class DownloadManager: @unchecked Sendable {
    
    public static let shared = DownloadManager()
    
    private let queue: OperationQueue
    private var operations: [URL: DownloadOperation] = [:]
    private var sync = DispatchQueue(label: "DownloadManager.operations", attributes: .concurrent)
    
    private init() {
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 3 // You can tune concurrency
    }
    
    // MARK: - Start Download
    public func startDownload(
        from url: URL,
        options: DownloadOptions,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void,
        maxRetries: Int = 3
    ) {
        // guard operations[url] == nil else { return }
        // Avoid duplicate downloads (thread safe read)
        var isDuplicate = false
        sync.sync {
            isDuplicate = operations[url] != nil
        }
        if isDuplicate { return }
        
        let operation = DownloadOperation(
            url: url,
            options: options,
            progress: progress,
            completion: { [weak self] result in
                completion(result)
                // Remove finished operation from dictionary
                self?.operations.removeValue(forKey: url)
            },
            maxRetries: maxRetries
        )
        
        sync.async(flags: .barrier) {
            self.operations[url] = operation
        }
        queue.addOperation(operation)
    }
    
    // MARK: - Pause Download
    public func pauseDownload(for url: URL) {
        sync.sync {
            self.operations[url]?.pause()
        }
    }
    
    // MARK: - Resume Download
    public func resumeDownload(for url: URL) {
        sync.sync {
            self.operations[url]?.resume()
        }
    }
    
    // MARK: - Cancel Download
    public func cancelDownload(for url: URL) {
        sync.sync {
            self.operations[url]?.cancel()
        }
        sync.async(flags: .barrier) {
            self.operations.removeValue(forKey: url)
        }
    }
    
    // MARK: - Cancel All
    public func cancelAllDownloads() {
        queue.cancelAllOperations()
        sync.async(flags: .barrier) {
            self.operations.removeAll()
        }
    }
    
    // MARK: - Introspection & Configuration
    public func activeDownloadURLs() -> [URL] {
        var keys: [URL] = []
        sync.sync {
            keys = Array(operations.keys)
        }
        return keys
    }
    
    public func setMaxConcurrentDownloads(_ count: Int) {
        queue.maxConcurrentOperationCount = count
    }
}
