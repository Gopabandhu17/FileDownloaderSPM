import Foundation

private struct TaskEntry {
    var task: URLSessionDownloadTask
    let options: DownloadOptions
    let progress: (Double) -> Void
    let completion: (Result<URL, Error>) -> Void
    var resumeData: Data?
}

final class NetworkManager: NSObject {
    
    static let shared = NetworkManager()
    private override init() {}
    
    // ✅ Set delegate = self
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    private var tasks: [URL: TaskEntry] = [:]
    
    func download(url: URL,
                  options: DownloadOptions,
                  onProgress: @escaping ((Double) -> Void),
                  onCompletion: @escaping ((Result<URL, Error>) -> Void)) {
        
        // Build Request
        var request = URLRequest(url: url)
        if let timeout = options.timeout {
            request.timeoutInterval = timeout
        }
        for (key, value) in options.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let task = session.downloadTask(with: request)
        tasks[url] = TaskEntry(task: task,
                               options: options,
                               progress: onProgress,
                               completion: onCompletion,
                               resumeData: nil)
        task.resume()
    }
    
    func pause(url: URL) {
        guard let entry = tasks[url] else { return }
        entry.task.cancel { [weak self] data in
            guard let self else { return }
            var updated = entry
            updated.resumeData = data
            self.tasks[url] = updated
        }
    }
    
    func resume(url: URL) {
        guard let entry = tasks[url], let resumeData = entry.resumeData else { return }
        let task = session.downloadTask(withResumeData: resumeData)
        var updated = entry
        updated.task = task
        updated.resumeData = nil
        tasks[url] = updated
        task.resume()
    }
    
    func cancel(url: URL) {
        tasks[url]?.task.cancel()
        tasks.removeValue(forKey: url)
    }
}

// MARK: - URLSessionDownloadDelegate
extension NetworkManager: URLSessionDownloadDelegate, @unchecked Sendable {
    
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let url = downloadTask.originalRequest?.url,
              let entry = tasks[url] else { return }
        
        entry.completion(.success(location))
        tasks.removeValue(forKey: url)
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0,
              let url = downloadTask.originalRequest?.url,
              let entry = tasks[url] else { return }
        
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        entry.progress(progress)
    }
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let url = task.originalRequest?.url,
              let entry = tasks[url] else { return }
        
        if let error {
            entry.completion(.failure(error))
            tasks.removeValue(forKey: url)
        }
    }
}
