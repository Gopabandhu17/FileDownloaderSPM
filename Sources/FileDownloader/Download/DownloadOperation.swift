import Foundation

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

        NetworkManager.shared.download(
            url: url,
            options: options,
            onProgress: { [weak self] progress in
                guard let self, !self.isCancelled else { return }
                self.progress(progress)
            },
            onCompletion: { [weak self] result in
                guard let self else { return }
//                if self.isCancelled {
//                    self.finish()
//                    return
//                }
                
                switch result {
                case .success(let fileURL):
                    // persist temp file to final destination
                    do {
                        let finalURL = try self.persistTempFile(at: fileURL)
                        self.completion(.success(finalURL))
                        self.finish()
                    } catch {
                        self.completion(.failure(error))
                        self.finish()
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
        )
    }
    
    // MARK: - Controls
    public func pause() {
        guard !isFinished && !isCancelled else { return }
        NetworkManager.shared.pause(url: url)
    }
    
    public func resume() {
        guard !isFinished && !isCancelled else { return }
        NetworkManager.shared.resume(url: url)
    }
    
    public override func cancel() {
        super.cancel()
        NetworkManager.shared.cancel(url: url)
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

extension DownloadOperation {
    
    private func persistTempFile(at tempURL: URL) throws -> URL {
        let fileManager = FileManager.default
        try ensureDirectoryExists(options.destinationDirectory)
        let filename = options.filename ?? UUID().uuidString
        var destination = options.destinationDirectory.appendingPathComponent(filename)
        
        if fileManager.fileExists(atPath: destination.path()) {
            if options.overwrite {
                try? fileManager.removeItem(at: destination)
            } else {
                destination = makeUniqueURL(for: destination)
            }
        }
        
        do {
            try fileManager.moveItem(at: tempURL, to: destination)
            return destination
        } catch {
            do {
                try fileManager.copyItem(at: tempURL, to: destination)
                try? fileManager.removeItem(at: tempURL)
                return destination
            } catch {
                throw NetworkError.fileMoveFailed(underlying: error)
            }
        }
    }
    
    private func ensureDirectoryExists(_ url: URL) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path()) {
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                throw NetworkError.directoryCreationFailed(underlying: error)
            }
        }
    }
    
    private func makeUniqueURL(for url: URL) -> URL {
        let fileManager = FileManager.default
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent()
        
        var candidate = url
        var index = 1
        
        while fileManager.fileExists(atPath: candidate.path()) {
            let newName = ext.isEmpty ? "\(base)\(index)" : "\(base)\(index).\(ext)"
            candidate = dir.appendingPathComponent(newName)
            index += 1
        }
        return candidate
    }
}
