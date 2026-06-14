import Foundation

struct ApprovalStatusResponse: Codable, Equatable {
    let status: String
    let ok: Bool
    let email: String?
    let cashierEmail: String?
    let name: String?
    let cashierName: String?
    let reason: String?
    let secondsRemaining: Int?
    let expiresAt: String?
    let cashMode: String?
    let expectedOpeningFloat: Double?
    let openingCountedFloat: Double?
    let openingVariance: Double?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case status, ok, email, cashierEmail, name, cashierName, reason
        case secondsRemaining, expiresAt, cashMode
        case expectedOpeningFloat, openingCountedFloat, openingVariance, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        email = try c.decodeIfPresent(String.self, forKey: .email)
        cashierEmail = try c.decodeIfPresent(String.self, forKey: .cashierEmail)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        cashierName = try c.decodeIfPresent(String.self, forKey: .cashierName)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        secondsRemaining = try c.decodeIfPresent(Int.self, forKey: .secondsRemaining)
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt)
        cashMode = try c.decodeIfPresent(String.self, forKey: .cashMode)
        expectedOpeningFloat = try c.decodeIfPresent(Double.self, forKey: .expectedOpeningFloat)
        openingCountedFloat = try c.decodeIfPresent(Double.self, forKey: .openingCountedFloat)
        openingVariance = try c.decodeIfPresent(Double.self, forKey: .openingVariance)
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }

    var displayEmail: String? {
        let candidates = [email, cashierEmail, name, cashierName]
        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}
