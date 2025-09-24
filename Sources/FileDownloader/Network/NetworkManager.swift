import Foundation

private actor TaskEntry {
    var task: URLSessionDownloadTask
    let options: DownloadOptions
    let progress: @Sendable (Double) -> Void
    let completion: @Sendable (Result<URL, Error>) -> Void
    var resumeData: Data?
    var lastProgressBytes: Int64 = 0
    
    init(
        task: URLSessionDownloadTask,
        options: DownloadOptions,
        progress: @escaping @Sendable (Double) -> Void,
        completion: @escaping @Sendable (Result<URL, Error>) -> Void,
        resumeData: Data? = nil
    ) {
        self.task = task
        self.options = options
        self.progress = progress
        self.completion = completion
        self.resumeData = resumeData
    }
    
    // MARK: Task Control
    func pause() {
        task.suspend()
    }
    
    func resume(session: URLSession) {
        switch task.state {
        case .suspended:
            task.resume()
        case .running:
            break
        default:
            // Task is completed or running, try to resume data if available
            if let data = resumeData {
                let newTask = session.downloadTask(withResumeData: data)
                task = newTask
                resumeData = nil
                newTask.resume()
            }
        }
    }
    
    func cancel() {
        task.cancel()
    }
    
    // MARK: progress and completion
    func reportProgress(_ progressValue: Double) {
        progress(progressValue)
    }
    
    func complete(with result: Result<URL, Error>) {
        completion(result)
    }
    
    // MARK: State access
    func getTask() -> URLSessionDownloadTask {
        return task
    }
    
    func storeResumeData(_ data: Data) {
        resumeData = data
    }
}

actor NetworkManager {
    
    static let shared = NetworkManager()
    private init() {}
    
    private lazy var delegate: NetworkManagerDelegate = NetworkManagerDelegate(manager: self)
    
    // ✅ Set delegate = proxy
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()
    
    private var tasks: [URL: TaskEntry] = [:]
    // private let sync: DispatchQueue = DispatchQueue(label: "NetworkManager.tasks", attributes: .concurrent)
    
    func download(url: URL,
                  options: DownloadOptions,
                  onProgress: @escaping @Sendable (Double) -> Void,
                  onCompletion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        
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
        self.tasks[url] = entry
        task.resume()
    }
    
    func pause(url: URL) {
        guard let entry: TaskEntry = self.tasks[url] else { return }
        Task {
            await entry.pause()
        }
    }
    
    func resume(url: URL) {
        guard let entry: TaskEntry = self.tasks[url] else { return }
        Task {
            await entry.resume(session: self.session)
        }
    }
    
    func cancel(url: URL) {
        guard let entry: TaskEntry = self.tasks[url] else { return }
        Task {
            await entry.cancel()
        }
    }
    
    // MARK: Internal methods for Delegate Callbacks
    public func handleDownloadFinished(url: URL, location: URL) {
        guard let entry = tasks[url] else { return }
        Task {
            await entry.complete(with: .success(location))
        }
        tasks.removeValue(forKey: url)
    }
    
    public func handleDownlaodFinishedWithData(url: URL, tempData: Data?) {
        guard let entry = tasks[url] else { return }
        
        if let data = tempData {
            Task {
                do {
                    let tempURL = try await DiskManager.shared.writeTempFile(data: data)
                    await entry.complete(with: .success(tempURL))
                } catch {
                    Task {
                        await entry.complete(with: .failure(NetworkError.invalidResponse))
                    }
                }
            }
        } else {
            Task {
                await entry.complete(with: .failure(NetworkError.invalidResponse))
            }
        }
        
        tasks.removeValue(forKey: url)
    }
    
    func handleProgress(url: URL, progress: Double) {
        guard let entry: TaskEntry = self.tasks[url] else { return }
        Task {
            await entry.reportProgress(progress)
        }
    }
    
    func handleTaskCompleted(url: URL, error: Error?) {
        guard let entry: TaskEntry = self.tasks.removeValue(forKey: url) else { return }
        if let error {
            if let urlError = error as? URLError, urlError.code == .cancelled {
                return
            }
            Task {
                await entry.complete(with: .failure(error))
            }
        }
    }
}

private final class NetworkManagerDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    
    private let manager: NetworkManager
    
    init(manager: NetworkManager) {
        self.manager = manager
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let url = downloadTask.originalRequest?.url else { return }
        
        let tempData: Data?
        
        do {
            tempData = try Data(contentsOf: location)
        } catch {
            Task {
                await manager.handleDownloadFinished(url: url, location: location)
            }
            return
        }
        
        Task {
            await manager.handleDownlaodFinishedWithData(url: url, tempData: tempData)
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
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task {
            await manager.handleProgress(url: url, progress: progress)
        }
    }
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard let url = task.originalRequest?.url else { return }
        Task {
            await manager.handleTaskCompleted(url: url, error: error)
        }
    }
}
