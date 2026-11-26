import Foundation

// How HuaSideload pairs with the watch. The watch reports which method it expects (support type in the link
// parameters), so Automatic is right for almost everyone; the manual choices exist for testing and bug reports.
enum PairingMethod: String, CaseIterable, Identifiable {
    case automatic
    case hiChain
    case hiChainLite
    case legacy

    static let storageKey = "pairingMethod"
    static let watchMACKey = "legacyWatchMAC"

    var id: String { rawValue }

    static var selected: PairingMethod {
        UserDefaults.standard.string(forKey: storageKey).flatMap(PairingMethod.init(rawValue:)) ?? .automatic
    }

    // What the watch's link parameters point to before security negotiation (support type 0x07)
    static func expected(supportType: Int) -> PairingMethod? {
        switch supportType {
        case 0: return .legacy
        case 2: return .hiChainLite
        case 1, 3, 4: return .hiChain
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .automatic: return L("Automatic (recommended)", "Otomatik (önerilen)")
        case .hiChain: return L("HiChain (newer watches)", "HiChain (yeni saatler)")
        case .hiChainLite: return L("HiChain Lite (experimental)", "HiChain Lite (deneysel)")
        case .legacy: return L("Legacy, no HiChain (experimental)", "Eski yöntem, HiChain'siz (deneysel)")
        }
    }

    var shortTitle: String {
        switch self {
        case .automatic: return L("Automatic", "Otomatik")
        case .hiChain: return "HiChain"
        case .hiChainLite: return "HiChain Lite"
        case .legacy: return L("Legacy", "Eski yöntem")
        }
    }

    // Which watches use it
    var watches: String {
        switch self {
        case .automatic:
            return L("Uses the method the watch asks for. Pick another one only if a developer asks you to, or to test.",
                     "Saatin istediği yöntemi kullanır. Başka birini yalnızca bir geliştirici isterse ya da test için seç.")
        case .hiChain:
            return L("Watch GT 2 / GT 3 and newer, Watch Fit series, newer bands.",
                     "Watch GT 2 / GT 3 ve sonrası, Watch Fit serisi, yeni bileklikler.")
        case .hiChainLite:
            return L("Some watches from around 2019–2020, e.g. Watch GT 2 Pro.",
                     "2019–2020 civarı bazı saatler, ör. Watch GT 2 Pro.")
        case .legacy:
            return L("First-generation Watch GT / GT Sport / GT Active and older bands. Needs the watch's Bluetooth MAC address.",
                     "İlk nesil Watch GT / GT Sport / GT Active ve eski bileklikler. Saatin Bluetooth MAC adresi gerekir.")
        }
    }

    // What has actually been tried on a real watch
    var tested: String? {
        switch self {
        case .automatic: return nil
        case .hiChain:
            return L("Tested: Watch GT 3 SE (developer), Watch GT 4, Band 11, Watch Fit 4 Pro (users).",
                     "Denendi: Watch GT 3 SE (geliştirici), Watch GT 4, Band 11, Watch Fit 4 Pro (kullanıcılar).")
        case .hiChainLite:
            return L("Tested by one fork owner on a Watch GT 2 Pro.",
                     "Bir fork sahibi Watch GT 2 Pro'da denedi.")
        case .legacy:
            return L("Not tested on a real watch yet. Ported from Gadgetbridge.",
                     "Henüz gerçek bir saatte denenmedi. Gadgetbridge'den çevrildi.")
        }
    }

    var isTested: Bool { self == .hiChain || self == .hiChainLite }
}
