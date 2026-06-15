import Foundation

enum NetworkErrorLogic {
    static func isOfflineLike(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let apiError = error as? PosAPIError {
            if case .invalidURL = apiError { return false }
            return false
        }
        if let urlError = error as? URLError {
            return isOfflineURLError(urlError)
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return isOfflineURLErrorCode(URLError.Code(rawValue: ns.code))
        }
        return false
    }

    static func isRetryableSyncError(_ error: Error) -> Bool {
        isOfflineLike(error)
    }

    private static func isOfflineURLError(_ error: URLError) -> Bool {
        isOfflineURLErrorCode(error.code)
    }

    private static func isOfflineURLErrorCode(_ code: URLError.Code) -> Bool {
        switch code {
        case .notConnectedToInternet,
             .timedOut,
             .cannotConnectToHost,
             .networkConnectionLost,
             .cannotFindHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed:
            return true
        default:
            return false
        }
    }
}
