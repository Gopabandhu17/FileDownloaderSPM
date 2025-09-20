import Foundation

public enum NetworkError: Error, LocalizedError {
    case badHTTPStatus(Int)
    case invalidResponse
    case fileMoveFailed(underlying: Error)
    case directoryCreationFailed(underlying: Error)
    case emptyURL
    case cancelled
    case paused
    
    public var errorDescription: String? {
        switch self {
        case .badHTTPStatus(let code):
            return "Unexpected HTTP status: \(code)"
        case .invalidResponse:
            return "Invalid or missing HTTP response"
        case .fileMoveFailed(let underlying):
            return "Failed to move download file \(underlying.localizedDescription)"
        case .directoryCreationFailed(let underlying):
            return "Failed to create destination directory \(underlying.localizedDescription)"
        case .emptyURL:
            return "URL is empty or invalid"
        case .cancelled:
            return "Download was cancelled"
        case .paused:
            return "Download was paused"
        }
    }
}
