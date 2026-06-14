import Foundation

struct PendingApprovalInfo: Codable, Equatable {
    let requestToken: String?
    let status: String?
    let expiresAt: String?
    let cashierEmail: String?
    let cashierName: String?
    let secondsRemaining: Int?
    let cashMode: String?
    let expectedOpeningFloat: Double?
    let openingCountedFloat: Double?
    let openingVariance: Double?
}

struct CashierSessionResponse: Codable, Equatable {
    let ok: Bool
    let pending: Bool
    let auth: String?
    let sub: String?
    let email: String?
    let name: String?
    let user: String?
    let cashierEmail: String?
    let supervisorApprovalRequired: Bool
    let idpEnabled: Bool
    let idpLoginUrl: String?
    let pinAllowed: Bool
    let awaitingTill: Bool
    let cashTillEnabled: Bool
    let cashEnabled: Bool?
    let cashMode: String?
    let expectedOpeningFloat: Double?
    let tillId: Int?
    let posSessionId: Int?
    let approval: PendingApprovalInfo?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok, pending, auth, sub, email, name, user, cashierEmail
        case supervisorApprovalRequired, idpEnabled, idpLoginUrl, pinAllowed
        case awaitingTill, cashTillEnabled, cashEnabled, cashMode
        case expectedOpeningFloat, tillId, posSessionId, approval, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        pending = try c.decodeIfPresent(Bool.self, forKey: .pending) ?? false
        auth = try c.decodeIfPresent(String.self, forKey: .auth)
        sub = try c.decodeIfPresent(String.self, forKey: .sub)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        user = try c.decodeIfPresent(String.self, forKey: .user)
        cashierEmail = try c.decodeIfPresent(String.self, forKey: .cashierEmail)
        supervisorApprovalRequired = try c.decodeIfPresent(Bool.self, forKey: .supervisorApprovalRequired) ?? false
        idpEnabled = try c.decodeIfPresent(Bool.self, forKey: .idpEnabled) ?? false
        idpLoginUrl = try c.decodeIfPresent(String.self, forKey: .idpLoginUrl)
        pinAllowed = try c.decodeIfPresent(Bool.self, forKey: .pinAllowed) ?? true
        awaitingTill = try c.decodeIfPresent(Bool.self, forKey: .awaitingTill) ?? false
        cashTillEnabled = try c.decodeIfPresent(Bool.self, forKey: .cashTillEnabled) ?? false
        cashEnabled = try c.decodeIfPresent(Bool.self, forKey: .cashEnabled)
        cashMode = try c.decodeIfPresent(String.self, forKey: .cashMode)
        expectedOpeningFloat = try c.decodeIfPresent(Double.self, forKey: .expectedOpeningFloat)
        tillId = try c.decodeIfPresent(Int.self, forKey: .tillId)
        posSessionId = try c.decodeIfPresent(Int.self, forKey: .posSessionId)
        approval = try c.decodeIfPresent(PendingApprovalInfo.self, forKey: .approval)
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }

    var displayUser: String? {
        guard ok else { return nil }
        for candidate in [user, email, cashierEmail, approval?.cashierEmail, name, approval?.cashierName] {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        if auth == "pin" { return "Cashier" }
        return nil
    }
}

struct OkResponse: Codable {
    let ok: Bool?
}
