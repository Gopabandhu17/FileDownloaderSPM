import Foundation

public class DownloadOperation: Operation, @unchecked Sendable {
    private let url: URL
    private let options: DownloadOptions
    private let downloader: FileDownloadManager
    private let progress: ((Double) -> Void)
    private let completion: ((Result<URL, Error>) -> Void)?
    private var isTaskFinished: Bool = false
    private var isTaskExecuting: Bool = false
    
    private var retryCount = 0
    private var maxRetries: Int
    
    public init(
        url: URL,
        options: DownloadOptions,
        downloader: FileDownloadManager,
        progress: @escaping ((Double) -> Void),
        completion: ((Result<URL, Error>) -> Void)?,
        maxRetries: Int
    ) {
        self.url = url
        self.options = options
        self.downloader = downloader
        self.progress = progress
        self.completion = completion
        self.maxRetries = maxRetries
        super.init()
    }
    
    public override var isAsynchronous: Bool { true }
    public override var isExecuting: Bool { isTaskExecuting }
    public override var isFinished: Bool { isTaskFinished }
    
    public override func start() {
        if isCancelled {
            finish()
            return
        }
        isTaskExecuting = true
        mainDownload()
    }
    
    private func mainDownload() {
        downloader.download(from: url, options: options, onProgress: progress) { [weak self] result in
            guard let self else { return }
            if self.isCancelled {
                self.finish()
                return
            }
            switch result {
            case .success(let fileURL):
                self.completion?(.success(fileURL))
                return
            case .failure(let error):
                if self.retryCount < self.maxRetries {
                    self.retryCount += 1
                    self.mainDownload()
                } else {
                    self.completion?(.failure(error))
                    self.finish()
                }
            }
        }
    }
    
    public override func cancel() {
        super.cancel()
        downloader.cancel()
        finish()
    }
    
    private func finish() {
        willChangeValue(forKey: "isExecuting")
        willChangeValue(forKey: "isFinished")
        isTaskExecuting = false
        isTaskFinished = true
        didChangeValue(forKey: "isExecuting")
        didChangeValue(forKey: "isFinished")
    }
}
