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
        sync.sync {
            guard let entry = tasks[url] else { return }
            entry.task.suspend()
        }
    }
    
    func resume(url: URL) {
        var needToResumeDataPath: Bool = false
        sync.sync {
            if let entry = tasks[url] {
                switch entry.task.state {
                case .suspended:
                    entry.task.resume()
                case .running:
                    break
                default:
                    if entry.resumeData != nil {
                        needToResumeDataPath = true
                    }
                }
            }
        }
        
        if needToResumeDataPath {
            sync.sync {
                guard let entry = tasks[url], let resumeData = entry.resumeData else { return }
                let task = session.downloadTask(withResumeData: resumeData)
                var updated = entry
                updated.task = task
                updated.resumeData = nil
                tasks[url] = updated
                let finalUpdated = updated
                sync.sync(flags: .barrier) {
                    self.tasks[url] = finalUpdated
                }
                task.resume()
            }
        }
    }
    
    func cancel(url: URL) {
        var entry: TaskEntry?
        sync.sync {
            entry = self.tasks[url]
        }
        guard let entry else { return }
        entry.task.cancel()
        sync.async(flags: .barrier) {
            self.tasks.removeValue(forKey: url)
        }
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
        sync.sync {
            entry = tasks[url]
        }
        guard let entry else { return }
        entry.completion(.success(location))
        sync.async(flags: .barrier) {
            self.tasks.removeValue(forKey: url)
        }
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
        sync.sync {
            entry = tasks[url]
        }
        guard let entry else { return }
        if let error {
            entry.completion(.failure(error))
            sync.async(flags: .barrier) {
                self.tasks.removeValue(forKey: url)
            }
        }
    }
}
