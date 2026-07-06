import UIKit

enum RegisterId {
    static var current: String {
        RegisterIdLogic.registerId(vendorUUID: UIDevice.current.identifierForVendor?.uuidString)
    }
}
