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
        // Validate inputs
        guard !url.absoluteString.isEmpty else {
            completion(.failure(NetworkError.emptyURL))
            return
        }
        
        guard maxRetries >= 0 else {
            completion(.failure(NetworkError.invalidRetryCount))
            return
        }
        
        // Check for duplicate download
        var isDuplicate = false
        sync.sync {
            isDuplicate = operations[url] != nil
        }
        if isDuplicate {
            completion(.failure(NetworkError.duplicateDownload))
            return
        }
        
        let operation = DownloadOperation(
            url: url,
            options: options,
            progress: progress,
            completion: { [weak self] result in
                guard let self else { return }
                completion(result)
                // Remove finished operation using thread-safe barrier write
                self.sync.async(flags: .barrier) {
                    self.operations.removeValue(forKey: url)
                }
            },
            maxRetries: maxRetries
        )
        
        // Add operation and start it automatically
        sync.async(flags: .barrier) {
            guard self.operations[url] == nil else {
                operation.cancel()
                completion(.failure(NetworkError.duplicateDownload))
                return
            }
            
            self.operations[url] = operation
            self.queue.addOperation(operation)
        }
    }
    
    // MARK: - Pause Download
    public func pauseDownload(for url: URL) {
        var operation: DownloadOperation?
        sync.sync {
            operation = self.operations[url]
        }
        guard let operation,
              !operation.isFinished,
              !operation.isCancelled else { return }
        operation.pause()
    }
    
    // MARK: - Resume Download
    public func resumeDownload(for url: URL) {
        var operation: DownloadOperation?
        sync.sync {
            operation = self.operations[url]
        }
        guard let operation,
              !operation.isFinished,
              !operation.isCancelled else { return }
        operation.resume()
    }
    
    // MARK: - Cancel Download
    public func cancelDownload(for url: URL) {
        var operation: DownloadOperation?
        // Automatically read and remove operation
        sync.sync {
            operation = self.operations.removeValue(forKey: url)
        }
        // Cancel the operation outside the lock
        operation?.cancel()
    }
    
    // MARK: - Cancel All
    public func cancelAllDownloads() {
        var operationsToCancel: [DownloadOperation] = []
        
        // Automatically get all operation and clear dictionary
        sync.sync(flags: .barrier) {
            operationsToCancel = Array(self.operations.values)
            operations.removeAll()
        }
        
        // Cancels operation outside the lock
        for operation in operationsToCancel {
            operation.cancel()
        }
        
        // Also cancel any operations still in the queue
        queue.cancelAllOperations()
    }
    
    // MARK: - Introspection & Configuration
    public func activeDownloadURLs(for url: URL) -> Bool {
        var isActive: Bool = false
        sync.sync {
            if let operation = operations[url] {
                isActive = !operation.isFinished && !operation.isCancelled
            }
        }
        return isActive
    }
    
    public func setMaxConcurrentDownloads(_ count: Int) {
        guard count > 0 else { return }
        queue.maxConcurrentOperationCount = count
    }
}
