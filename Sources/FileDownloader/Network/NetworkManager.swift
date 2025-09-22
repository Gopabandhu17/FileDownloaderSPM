import Foundation

private struct TaskEntry: @unchecked Sendable {
    var task: URLSessionDownloadTask
    let options: DownloadOptions
    let progress: (Double) -> Void
    let completion: (Result<URL, Error>) -> Void
    var resumeData: Data?
    var lastProgressBytes: Int64 = 0
}

final class NetworkManager: NSObject {
    
    static let shared = NetworkManager()
    private override init() {}
    
    // ✅ Set delegate = self
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    private var tasks: [URL: TaskEntry] = [:]
    private let sync: DispatchQueue = DispatchQueue(label: "NetworkManager.tasks", attributes: .concurrent)
    
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
        let entry = TaskEntry(task: task,
                               options: options,
                               progress: onProgress,
                               completion: onCompletion,
                               resumeData: nil)
        sync.sync(flags: .barrier) {
            self.tasks[url] = entry
        }
        task.resume()
    }
    
    func pause(url: URL) {
        var task: URLSessionDownloadTask? = nil
        sync.sync {
            task = self.tasks[url]?.task
        }
        task?.suspend()
    }
    
    func resume(url: URL) {
        
        var shouldCreateNewTask: Bool = false
        var resumeData: Data?
        var entry: TaskEntry?
        
        sync.sync {
            entry = tasks[url]
            if let currentEntry = entry {
                switch currentEntry.task.state {
                case .suspended:
                    currentEntry.task.resume()
                    return
                case .running: return
                default:
                    if let data = currentEntry.resumeData {
                        shouldCreateNewTask = true
                        resumeData = data
                    }
                }
            }
        }
        
        if shouldCreateNewTask,
           let resumeData = resumeData,
           let entry = entry {
            let newTask = session.downloadTask(withResumeData: resumeData)
            var updatedEntry = entry
            updatedEntry.task = newTask
            updatedEntry.resumeData = nil
            
            sync.sync(flags: .barrier) {
                self.tasks[url] = updatedEntry
            }
            
            newTask.resume()
        }
    }
    
    func cancel(url: URL) {
        var entry: TaskEntry?
        sync.sync(flags: .barrier) {
            entry = self.tasks.removeValue(forKey: url)
        }
        entry?.task.cancel()
    }
}

// MARK: - URLSessionDownloadDelegate
extension NetworkManager: URLSessionDownloadDelegate, @unchecked Sendable {
    
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let url = downloadTask.originalRequest?.url else { return }
        var entry: TaskEntry?
        
        sync.sync(flags: .barrier) {
            entry = self.tasks.removeValue(forKey: url)
        }
        
        guard let entry else { return }
        entry.completion(.success(location))
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0,
              let url = downloadTask.originalRequest?.url else { return }
        var entry: TaskEntry?
        sync.sync {
            entry = tasks[url]
        }
        guard let entry else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        entry.progress(progress)
    }
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let url = task.originalRequest?.url else { return }
        var entry: TaskEntry?
        sync.sync(flags: .barrier) {
            entry = self.tasks.removeValue(forKey: url)
        }
        guard let entry else { return }
        if let error {
            if let urlError = error as? URLError,
               urlError.code == .cancelled {
                // Don't call the completion for cancelled task
                return
            }
            entry.completion(.failure(error))
        }
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didResumeAtOffset fileOffset: Int64,
        expectedTotalBytes: Int64
    ) {
        // Handle resume offset if needed
    }
}
