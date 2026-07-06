import Foundation

struct CashierSessionResponse: Codable, Equatable {
    let ok: Bool
    let auth: String?
    let sub: String?
    let email: String?
    let name: String?
    let user: String?
    let cashierEmail: String?
    let idpEnabled: Bool
    let idpLoginUrl: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok, auth, sub, email, name, user, cashierEmail, idpEnabled, idpLoginUrl, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        auth = try c.decodeIfPresent(String.self, forKey: .auth)
        sub = try c.decodeIfPresent(String.self, forKey: .sub)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        user = try c.decodeIfPresent(String.self, forKey: .user)
        cashierEmail = try c.decodeIfPresent(String.self, forKey: .cashierEmail)
        idpEnabled = try c.decodeIfPresent(Bool.self, forKey: .idpEnabled) ?? false
        idpLoginUrl = try c.decodeIfPresent(String.self, forKey: .idpLoginUrl)
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }

    var displayUser: String? {
        guard ok else { return nil }
        for candidate in [user, email, cashierEmail, name] {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}

struct OkResponse: Codable {
    let ok: Bool?
}
