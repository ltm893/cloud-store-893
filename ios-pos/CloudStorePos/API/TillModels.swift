import Foundation

struct TillDenomination: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let value: Double
}

struct TillConfigResponse: Codable, Equatable {
    let cashTillEnabled: Bool
    let expectedOpeningFloat: Double?
    let denominations: [TillDenomination]

    enum CodingKeys: String, CodingKey {
        case cashTillEnabled, expectedOpeningFloat, denominations
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cashTillEnabled = try c.decodeIfPresent(Bool.self, forKey: .cashTillEnabled) ?? false
        expectedOpeningFloat = try c.decodeIfPresent(Double.self, forKey: .expectedOpeningFloat)
        denominations = try c.decodeIfPresent([TillDenomination].self, forKey: .denominations) ?? []
    }
}

struct SubmitOpeningTillRequest: Encodable {
    let cashMode: String
    let denominations: [String: Int]?
    let countedTotal: Double?
}

struct SubmitOpeningTillResponse: Codable, Equatable {
    let ok: Bool
    let pending: Bool
    let awaitingTill: Bool
    let cashMode: String?
    let cashEnabled: Bool?
    let openingCountedFloat: Double?
    let openingVariance: Double?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok, pending, awaitingTill, cashMode, cashEnabled
        case openingCountedFloat, openingVariance, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        pending = try c.decodeIfPresent(Bool.self, forKey: .pending) ?? false
        awaitingTill = try c.decodeIfPresent(Bool.self, forKey: .awaitingTill) ?? false
        cashMode = try c.decodeIfPresent(String.self, forKey: .cashMode)
        cashEnabled = try c.decodeIfPresent(Bool.self, forKey: .cashEnabled)
        openingCountedFloat = try c.decodeIfPresent(Double.self, forKey: .openingCountedFloat)
        openingVariance = try c.decodeIfPresent(Double.self, forKey: .openingVariance)
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }
}
