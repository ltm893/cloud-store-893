import Foundation

enum APIErrorMessageLogic {
    static func message(fromBody body: String?) -> String? {
        guard let body, !body.isEmpty,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? String,
              !error.isEmpty
        else { return nil }
        return error
    }

    static func httpErrorMessage(statusCode: Int, body: String?) -> String {
        if let parsed = message(fromBody: body) { return parsed }
        if let body, !body.isEmpty, !body.hasPrefix("{") { return body }
        return "Server error (\(statusCode))"
    }
}
