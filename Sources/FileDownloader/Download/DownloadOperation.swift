import Foundation

public class DownloadOperation: Operation, @unchecked Sendable {
    
    private let url: URL
    private let options: DownloadOptions
    private let progress: (Double) -> Void
    private let completion: (Result<URL, Error>) -> Void
    private let maxRetries: Int
    
    private var retryCount = 0
    private var isTaskExecuting = false
    private var isTaskFinished = false
    private let stateLock = NSLock()
    
    public init(
        url: URL,
        options: DownloadOptions,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void,
        maxRetries: Int = 3
    ) {
        self.url = url
        self.options = options
        self.progress = progress
        self.completion = completion
        self.maxRetries = maxRetries
        super.init()
    }
    
    // MARK: - Operation State Overrides
    public override var isAsynchronous: Bool { true }
    public override var isExecuting: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isTaskExecuting
    }
    public override var isFinished: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isTaskFinished
    }
    
    public override func start() {
        if isCancelled {
            finish()
            return
        }
        
        willChangeValue(forKey: "isExecuting")
        stateLock.lock()
        isTaskExecuting = true
        stateLock.unlock()
        didChangeValue(forKey: "isExecuting")
        
        startDownload()
    }
    
    private func startDownload() {
        guard !isCancelled else {
            finish()
            return
        }

        Task {
            await NetworkManager.shared.download(
                url: url,
                options: options,
                onProgress: { [weak self] progress in
                    guard let self, !self.isCancelled else { return }
                    self.progress(progress)
                },
                onCompletion: { [weak self] result in
                    guard let self else { return }
                    self.handleDownloadResults(result)
                }
            )
        }
    }
    
    private func handleDownloadResults(_ result: Result<URL, Error>) {
        switch result {
        case .success(let fileURL):
            Task {
                do {
                    let finalURL = try await DiskManager.shared.persistTempFile(
                        from: fileURL,
                        to: options.destinationDirectory,
                        filename: options.filename,
                        overwrite: options.overwrite
                    )
                    self.completion(.success(finalURL))
                    finish()
                } catch {
                    self.completion(.failure(error))
                    self.finish()
                }
            }
        case .failure(let error):
            if self.retryCount < self.maxRetries {
                self.retryCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.startDownload()
                }
            } else {
                self.completion(.failure(error))
                self.finish()
            }
        }
    }
    
    // MARK: - Controls
    public func pause() {
        guard !isFinished && !isCancelled else { return }
        Task {
            await NetworkManager.shared.pause(url: url)
        }
    }
    
    public func resume() {
        guard !isFinished && !isCancelled else { return }
        Task {
            await NetworkManager.shared.resume(url: url)
        }
    }
    
    public override func cancel() {
        super.cancel()
        Task {
            await NetworkManager.shared.cancel(url: url)
        }
        finish()
    }
    
    // MARK: - Finish Helper
    private func finish() {
        willChangeValue(forKey: "isExecuting")
        willChangeValue(forKey: "isFinished")
        
        stateLock.lock()
        isTaskExecuting = false
        isTaskFinished = true
        stateLock.unlock()
        
        didChangeValue(forKey: "isExecuting")
        didChangeValue(forKey: "isFinished")
    }
}
