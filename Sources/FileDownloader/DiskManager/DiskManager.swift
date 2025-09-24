import Foundation

actor DiskManager {
    
    static let shared = DiskManager()
    private init() {}
    
    func persistTempFile(
        from tempURL: URL,
        to destinationDirectory: URL,
        filename: String? = nil,
        overwrite: Bool = false
    ) throws -> URL {
        let fileManager = FileManager.default
        try ensureDirectoryExists(destinationDirectory)
        let filename = filename ?? UUID().uuidString
        var destination = destinationDirectory.appendingPathComponent(filename)
        
        if fileManager.fileExists(atPath: destination.path()) {
            if overwrite {
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

extension DiskManager {
    func createTempFileURL(filename: String? = nil) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileName = filename ?? "download_\(UUID().uuidString).tmp"
        return tempDir.appending(component: tempFileName)
    }
    
    func writeTempFile(data: Data) throws -> URL {
        let tempURL = createTempFileURL()
        try data.write(to: tempURL)
        return tempURL
    }
}
