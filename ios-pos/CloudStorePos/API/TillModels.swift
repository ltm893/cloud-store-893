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
    let awaitingTillToken: String?
}

struct SubmitOpeningTillResponse: Codable, Equatable {
    let ok: Bool
    let pending: Bool
    let resumed: Bool
    let awaitingTill: Bool
    let requestToken: String?
    let cashMode: String?
    let cashEnabled: Bool?
    let openingCountedFloat: Double?
    let openingVariance: Double?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok, pending, resumed, awaitingTill, requestToken, cashMode, cashEnabled
        case openingCountedFloat, openingVariance, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        pending = try c.decodeIfPresent(Bool.self, forKey: .pending) ?? false
        resumed = try c.decodeIfPresent(Bool.self, forKey: .resumed) ?? false
        awaitingTill = try c.decodeIfPresent(Bool.self, forKey: .awaitingTill) ?? false
        requestToken = try c.decodeIfPresent(String.self, forKey: .requestToken)
        cashMode = try c.decodeIfPresent(String.self, forKey: .cashMode)
        cashEnabled = try c.decodeIfPresent(Bool.self, forKey: .cashEnabled)
        openingCountedFloat = try c.decodeIfPresent(Double.self, forKey: .openingCountedFloat)
        openingVariance = try c.decodeIfPresent(Double.self, forKey: .openingVariance)
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }
}

struct CloseTillPreviewResponse: Codable, Equatable {
    let ok: Bool
    let creditOnly: Bool
    let cartBlocked: Bool
    let openingCountedFloat: Double?
    let expectedCloseFloat: Double?
    let cashSalesTotal: Double?
    let changeGivenTotal: Double?
    let denominations: [TillDenomination]
    let supervisorApprovalRequired: Bool
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok, creditOnly, cartBlocked, openingCountedFloat, expectedCloseFloat
        case cashSalesTotal, changeGivenTotal, denominations, supervisorApprovalRequired, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        creditOnly = try c.decodeIfPresent(Bool.self, forKey: .creditOnly) ?? false
        cartBlocked = try c.decodeIfPresent(Bool.self, forKey: .cartBlocked) ?? false
        openingCountedFloat = try c.decodeIfPresent(Double.self, forKey: .openingCountedFloat)
        expectedCloseFloat = try c.decodeIfPresent(Double.self, forKey: .expectedCloseFloat)
        cashSalesTotal = try c.decodeIfPresent(Double.self, forKey: .cashSalesTotal)
        changeGivenTotal = try c.decodeIfPresent(Double.self, forKey: .changeGivenTotal)
        denominations = try c.decodeIfPresent([TillDenomination].self, forKey: .denominations) ?? []
        supervisorApprovalRequired = try c.decodeIfPresent(Bool.self, forKey: .supervisorApprovalRequired) ?? false
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }
}

struct SubmitCloseTillRequest: Encodable {
    let cashMode: String
    let denominations: [String: Int]?
    let countedTotal: Double?
    let registerId: String?
}

struct SubmitCloseTillResponse: Codable, Equatable {
    let ok: Bool
    let pending: Bool
    let approved: Bool
    let closeToken: String?
    let cashMode: String?
    let closeVariance: Double?
    let expectedCloseFloat: Double?
    let countedCloseFloat: Double?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok, pending, approved, closeToken, cashMode, closeVariance
        case expectedCloseFloat, countedCloseFloat, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        pending = try c.decodeIfPresent(Bool.self, forKey: .pending) ?? false
        approved = try c.decodeIfPresent(Bool.self, forKey: .approved) ?? false
        closeToken = try c.decodeIfPresent(String.self, forKey: .closeToken)
        cashMode = try c.decodeIfPresent(String.self, forKey: .cashMode)
        closeVariance = try c.decodeIfPresent(Double.self, forKey: .closeVariance)
        expectedCloseFloat = try c.decodeIfPresent(Double.self, forKey: .expectedCloseFloat)
        countedCloseFloat = try c.decodeIfPresent(Double.self, forKey: .countedCloseFloat)
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }
}

struct CloseTillStatusResponse: Codable, Equatable {
    let status: String?
    let ok: Bool
    let pending: Bool
    let closeToken: String?
    let secondsRemaining: Int?
    let cashMode: String?
    let expectedCloseFloat: Double?
    let countedCloseFloat: Double?
    let closeVariance: Double?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case status, ok, pending, closeToken, secondsRemaining, cashMode
        case expectedCloseFloat, countedCloseFloat, closeVariance, reason
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        pending = try c.decodeIfPresent(Bool.self, forKey: .pending) ?? false
        closeToken = try c.decodeIfPresent(String.self, forKey: .closeToken)
        secondsRemaining = try c.decodeIfPresent(Int.self, forKey: .secondsRemaining)
        cashMode = try c.decodeIfPresent(String.self, forKey: .cashMode)
        expectedCloseFloat = try c.decodeIfPresent(Double.self, forKey: .expectedCloseFloat)
        countedCloseFloat = try c.decodeIfPresent(Double.self, forKey: .countedCloseFloat)
        closeVariance = try c.decodeIfPresent(Double.self, forKey: .closeVariance)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
    }
}
