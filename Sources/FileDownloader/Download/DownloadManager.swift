import Foundation

public actor DownloadManager {
    
    public static let shared = DownloadManager()
    
    private let queue: OperationQueue
    private var operations: [URL: DownloadOperation] = [:]
    
    private init() {
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 3 // You can tune concurrency
    }
    
    // MARK: - Start Download
    public func startDownload(
        from url: URL,
        options: DownloadOptions,
        progress: @escaping @Sendable (Double) -> Void,
        completion: @escaping @Sendable (Result<URL, Error>) -> Void,
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
        guard operations[url] == nil else {
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
                Task {
                    await self.removeFinishedOperation(for: url)
                }
            },
            maxRetries: maxRetries
        )
        
        self.operations[url] = operation
        self.queue.addOperation(operation)
    }
    
    private func removeFinishedOperation(for url: URL) {
        operations.removeValue(forKey: url)
    }
    
    // MARK: - Pause Download
    public func pauseDownload(for url: URL) {
        guard let operation = operations[url],
              !operation.isFinished,
              !operation.isCancelled else { return }
        operation.pause()
    }
    
    // MARK: - Resume Download
    public func resumeDownload(for url: URL) {
        guard let operation = operations[url],
              !operation.isFinished,
              !operation.isCancelled else { return }
        operation.resume()
    }
    
    // MARK: - Cancel Download
    public func cancelDownload(for url: URL) {
        let operation = self.operations.removeValue(forKey: url)
        operation?.cancel()
    }
    
    // MARK: - Cancel All
    public func cancelAllDownloads() {
        let operationsToCancel: [DownloadOperation] = Array(self.operations.values)
        operations.removeAll()
        for operation in operationsToCancel {
            operation.cancel()
        }
        queue.cancelAllOperations()
    }
    
    // MARK: - Introspection & Configuration
    public func activeDownloadURLs(for url: URL) -> Bool {
        if let operation = operations[url] {
            return !operation.isFinished && !operation.isCancelled
        }
        return false
    }
    
    public func setMaxConcurrentDownloads(_ count: Int) {
        guard count > 0 else { return }
        queue.maxConcurrentOperationCount = count
    }
}
