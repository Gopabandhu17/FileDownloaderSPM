import Foundation

actor TaskEntry {
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
