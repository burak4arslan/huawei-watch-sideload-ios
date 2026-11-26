import SwiftUI

// Watch tab: which pairing method to use, which watches use which method, and what has been tested
struct PairingMethodSection: View {
    @ObservedObject var link: WatchLink
    @AppStorage(PairingMethod.storageKey) private var methodRaw = PairingMethod.automatic.rawValue
    @AppStorage(PairingMethod.watchMACKey) private var typedMAC = ""
    @State private var showsGuide = false

    private var method: PairingMethod { PairingMethod(rawValue: methodRaw) ?? .automatic }
    // The method that will actually run
    private var effective: PairingMethod? { method == .automatic ? link.detectedPairingMethod : method }
    private var macIsValid: Bool { LegacyPairing.normalizedMAC(typedMAC) != nil }

    var body: some View {
        Section {
            Picker(L("Method", "Yöntem"), selection: $methodRaw) {
                ForEach(PairingMethod.allCases) { option in
                    Text(option.shortTitle).tag(option.rawValue)
                }
            }
            .disabled(link.busy != nil)

            if let detected = link.detectedPairingMethod {
                LabeledContent(L("This watch asks for", "Bu saatin istediği"), value: detected.shortTitle)
                if method != .automatic && method != detected {
                    Label(L("Your choice differs from what the watch asks for. Pairing will most likely fail; set it back to Automatic.",
                            "Seçimin saatin istediğinden farklı. Eşleşme büyük ihtimalle başarısız olur; Otomatik'e geri al."),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            if method != .automatic {
                methodInfo(method)
            } else if let effective {
                methodInfo(effective)
            }

            if effective == .legacy || method == .legacy {
                macField
            }

            DisclosureGroup(L("Which method does my watch use?", "Saatim hangi yöntemi kullanıyor?"), isExpanded: $showsGuide) {
                ForEach(PairingMethod.allCases.filter { $0 != .automatic }) { option in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(option.title).font(.subheadline.weight(.semibold))
                        Text(option.watches).font(.footnote)
                        if let tested = option.tested {
                            testedLabel(option, tested)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text(L("Pairing method", "Eşleşme yöntemi"))
        } footer: {
            Text(L("You don't need to change anything here: on Automatic the watch tells the app which method it expects, and if it needs more (the legacy method needs the watch's MAC address), the app asks when you tap Pair.",
                   "Burada bir şey değiştirmen gerekmez: Otomatik'te saat hangi yöntemi beklediğini uygulamaya kendisi söyler; fazlası gerekirse (eski yöntem saatin MAC adresini ister) uygulama Eşleş'e bastığında sorar."))
        }
    }

    private func methodInfo(_ option: PairingMethod) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(option.watches).font(.footnote)
            if let tested = option.tested { testedLabel(option, tested) }
        }
    }

    private func testedLabel(_ option: PairingMethod, _ text: String) -> some View {
        Label(text, systemImage: option.isTested ? "checkmark.seal.fill" : "flask.fill")
            .font(.footnote)
            .foregroundStyle(option.isTested ? .green : .orange)
    }

    @ViewBuilder private var macField: some View {
        LabeledContent(L("Watch MAC", "Saatin MAC'i")) {
            TextField("AA:BB:CC:DD:EE:FF", text: $typedMAC)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.body.monospaced())
                .onSubmit { if let mac = LegacyPairing.normalizedMAC(typedMAC) { typedMAC = mac } }
        }
        if !typedMAC.isEmpty && !macIsValid {
            Label(L("That doesn't look like a MAC address (12 hex digits).", "Bu bir MAC adresine benzemiyor (12 onaltılık hane)."),
                  systemImage: "xmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
        } else if typedMAC.isEmpty, let found = link.advertisedMACForConnectedWatch {
            Label(L("Found in the watch's Bluetooth signal: \(found). Check it on the watch; type it here if it differs.",
                    "Saatin Bluetooth sinyalinde bulundu: \(found). Saatte kontrol et; farklıysa buraya yaz."),
                  systemImage: "antenna.radiowaves.left.and.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Text(L("iPhones can't read a watch's MAC address, so the legacy method needs it from you. On the watch: Settings → About → MAC address.",
                   "iPhone bir saatin MAC adresini okuyamıyor, bu yüzden eski yöntem onu senden istiyor. Saatte: Ayarlar → Hakkında → MAC adresi."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
