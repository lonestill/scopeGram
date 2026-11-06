import Cocoa
import TelegramCore
import TelegramContext

public func formatPhoneNumber(context: any AccountContextProtocol, number: String) -> String {
    if UserDefaults.standard.bool(forKey: "scopegram.hidePhoneNumbers") || UserDefaults.standard.bool(forKey: "chargedGram.hidePhoneNumbers") {
        if !number.isEmpty {
            return "+* *** ***-**-**"
        }
    }
    if let pattern = lookupPatternByNumber(number, configuration: PhoneNumberUtilsHooks.shared.currentCountriesConfiguration(context).with { $0 }) {
        return "+\(formatPhoneNumberToMask(number, mask: pattern))"
    } else {
        return formatPhoneNumber(number)
    }
}
