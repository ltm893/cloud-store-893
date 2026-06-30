import Foundation

enum PinSignInLogic {
    static let maxPinLength = 8

    static func maskedPin(_ input: String) -> String {
        String(repeating: "•", count: input.count)
    }

    static func appendPinDigit(current: String, digit: Character) -> String {
        guard digit.isNumber, current.count < maxPinLength else { return current }
        return current + String(digit)
    }

    static func backspacePin(_ current: String) -> String {
        String(current.dropLast())
    }
}
