import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var link = WatchLink()
    // Changing the language re-renders the screen; L() reads the same setting
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.current.rawValue
    @State private var copied = false
    @State private var message = ""
    @FocusState private var messageFocused: Bool
    // Filming mode: only what a video needs (no log controls, no feature sections, no identity buttons).
    // Offered only when a feature asks for it (WatchFeature.offersFilmMode); the plain app never shows it.
    @AppStorage("filmModeV2") private var filmModeOn = false
    @AppStorage(HuaweiSession.diagnosticsKey) private var pairingDiagnostics = false
    // Kept in the Keychain (CredentialStore), not in UserDefaults
    @State private var huaweiAccountId = CredentialStore.shared.string(CredentialStore.huaweiAccountKey) ?? ""
    @AppStorage(WatchLink.pairingSetupKey) private var sendsPairingSetup = false
    @State private var confirmingFirstPairing = false
    @AppStorage(PairingMethod.watchMACKey) private var watchMAC = ""
    @State private var macDraft = ""
    private var filmModeOffered: Bool { link.features.contains { $0.offersFilmMode } }
    private var filmMode: Bool { filmModeOffered && filmModeOn }

    enum Tab: Hashable { case watch, install, features, log }
    @State private var tab: Tab = .watch

    var body: some View {
        TabView(selection: $tab) {
            page(AppInfo.displayName) {
                statusSection
                if link.connectedName == nil && !link.isConnecting {
                    devicesSection
                    if !filmMode { PairingMethodSection(link: link) }
                } else {
                    watchSection
                    if !filmMode { PairingMethodSection(link: link) }
                    if link.isPaired { notificationSection }
                    if link.hasSavedPairing && !filmMode {
                        Section {
                            Button(L("Forget pairing", "Eşleşmeyi unut"), role: .destructive) { link.forgetPairing() }
                        } footer: {
                            Text(L("Use this if the watch was reset or pairing broke. The next pairing starts from the PIN step.",
                                   "Saat sıfırlandıysa ya da eşleşme bozulduysa kullan. Sonraki eşleşme PIN adımından başlar."))
                        }
                    }
                }
            }
            .tabItem { Label(L("Watch", "Saat"), systemImage: "watch.analog") }
            .tag(Tab.watch)

            page(L("Install", "Yükle")) {
                if link.isPaired {
                    InstallTab(link: link, filmMode: filmMode,
                               hiddenApps: filmMode ? Set(link.features.flatMap(\.filmModeHiddenApps)) : [])
                } else {
                    pairFirstSection
                }
            }
            .tabItem { Label(L("Install", "Yükle"), systemImage: "square.and.arrow.down") }
            .tag(Tab.install)

            page(L("Features", "Özellikler")) {
                if link.isPaired {
                    WatchSpeakerSection(speaker: link.speaker)
                    // Feature sections (navigation, remote control etc.); never in filming mode
                    if !filmMode {
                        ForEach(link.features.indices, id: \.self) { index in
                            link.features[index].sections()
                        }
                    }
                } else {
                    pairFirstSection
                }
            }
            .tabItem { Label(L("Features", "Özellikler"), systemImage: "sparkles") }
            .tag(Tab.features)

            page(L("Log", "Log")) {
                logSection
            }
            .tabItem { Label(L("Log", "Log"), systemImage: "list.bullet.rectangle") }
            .tag(Tab.log)
        }
        // While filming, identities (UDID, serial number, MAC) always stay masked, in the log too
        .onAppear { if filmMode { link.revealIdentity = false } }
        .onChange(of: filmMode) { _, on in if on { link.revealIdentity = false } }
    }

    // One tab: a list with the title and the shared toolbar (filming mode, language)
    private func page<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            List { content() }
                // Feature sections don't know about the language: rebuild the list when it changes
                .id(language)
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle(title)
                .toolbar {
                    if filmModeOffered {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { filmModeOn.toggle() } label: {
                                Label(L("Filming", "Çekim"), systemImage: filmMode ? "video.fill" : "video")
                                    .labelStyle(.titleAndIcon)
                            }
                            .tint(filmMode ? .red : nil)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker(L("Language", "Dil"), selection: $language) {
                                ForEach(AppLanguage.allCases) { Text($0.title).tag($0.rawValue) }
                            }
                        } label: {
                            Image(systemName: "globe")
                        }
                        .accessibilityLabel(L("Language", "Dil"))
                    }
                }
        }
    }

    private var pairFirstSection: some View {
        Section {
            Button(L("Pair with the watch first", "Önce saatle eşleş")) { tab = .watch }
                .fontWeight(.semibold)
        } footer: {
            Text(L("This needs an encrypted connection to the watch. Connect and pair on the Watch tab.",
                   "Bunun için saatle şifreli bağlantı gerekiyor. Saat sekmesinden bağlan ve eşleş."))
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            if !filmMode {
                LabeledContent(L("Bluetooth", "Bluetooth"), value: link.bluetoothState)
            }
            LabeledContent(L("Watch", "Saat"), value: link.connectedName ?? (link.isConnecting ? L("Connecting…", "Bağlanıyor…") : L("Not connected", "Bağlı değil")))
            LabeledContent(L("Pairing", "Eşleşme"), value: link.pairingStage.label)
            if let battery = link.battery {
                LabeledContent(L("Battery", "Pil"), value: "\(battery)%")
            }
            if !filmMode {
                ForEach(link.watchInfo, id: \.self) { Text(link.display($0)).font(.callout) }
            }
            // In filming mode only once paired (an identity left over from the last session must not show before pairing)
            if let udid = link.watchUDID, link.isPaired || !filmMode {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("UDID (for the debug profile)", "UDID (geliştirici profili için)")).font(.caption).foregroundStyle(.secondary)
                    Text(link.revealIdentity ? udid : String(repeating: "•", count: 16))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                if !filmMode {
                    Button(L("Copy UDID", "UDID'yi kopyala")) { UIPasteboard.general.string = udid }
                }
            }
        } header: {
            HStack {
                Text(L("Status", "Durum"))
                Spacer()
                if !filmMode {
                    Button(link.revealIdentity ? L("Hide identity", "Kimliği gizle") : L("Show identity", "Kimliği göster")) {
                        link.revealIdentity.toggle()
                    }
                    .font(.caption)
                }
            }
            .textCase(nil)
        } footer: {
            if !filmMode {
                Text(L("UDID, serial number and MAC addresses are hidden on screen and in the log (e.g. while filming). \"Show identity\" reveals them.",
                       "UDID, seri no ve MAC adresleri ekranda ve kayıtlarda gizli tutulur (video çekerken görünmesin diye). \"Kimliği göster\" ile açılır."))
            }
        }
    }

    private var devicesSection: some View {
        Section {
            Button(link.isScanning ? L("Scanning…", "Aranıyor…") : L("Find watch", "Saati ara")) { link.startScan() }
                .disabled(link.isScanning)
            ForEach(link.devices) { device in
                Button { link.connect(device) } label: { DeviceRow(device: device) }
            }
        } header: {
            Text(L("Devices", "Cihazlar"))
        } footer: {
            Text(L("If the watch is connected to Huawei Health it shows up as \"connected to phone\". Tap it.",
                   "Saat Huawei Health'e bağlıysa \"telefona bağlı\" olarak görünür. Ona dokun."))
        }
    }

    private var watchSection: some View {
        Section {
            if let busy = link.busy {
                HStack { ProgressView(); Text(busy).foregroundStyle(.secondary) }
            }
            if !link.isPaired {
                // A first pairing (PIN + HiChain) creates this app's own pairing on the watch; a saved key only reconnects
                Button(link.hasSavedPairing ? L("Pair (saved key)", "Eşleş (kayıtlı anahtarla)") : L("Pair", "Eşleş")) {
                    if link.hasSavedPairing { link.pair() } else { confirmingFirstPairing = true }
                }
                .disabled(!link.huaweiChannelReady || link.busy != nil)
                .fontWeight(.semibold)
                .alert(L("Watch MAC address needed", "Saatin MAC adresi gerekiyor"), isPresented: $link.needsWatchMAC) {
                    TextField("AA:BB:CC:DD:EE:FF", text: $macDraft)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button(L("Pair", "Eşleş")) {
                        if let mac = LegacyPairing.normalizedMAC(macDraft) {
                            watchMAC = mac
                            link.pair()
                        } else {
                            link.needsWatchMAC = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { link.needsWatchMAC = true }
                        }
                    }
                    Button(L("Cancel", "Vazgeç"), role: .cancel) {}
                } message: {
                    Text(L("This watch uses the older pairing method (no HiChain, experimental), which needs the watch's Bluetooth MAC address. iPhones can't read it, so please type it in. On the watch: Settings → About → MAC address.",
                           "Bu saat eski eşleşme yöntemini kullanıyor (HiChain'siz, deneysel) ve bunun için saatin Bluetooth MAC adresi gerekiyor. iPhone bunu okuyamıyor, lütfen sen yaz. Saatte: Ayarlar → Hakkında → MAC adresi."))
                }
                .onChange(of: link.needsWatchMAC) { _, asking in
                    if asking { macDraft = watchMAC.isEmpty ? (link.advertisedMACForConnectedWatch ?? "") : watchMAC }
                }
                .confirmationDialog(L("First pairing with this watch", "Bu saatle ilk eşleşme"), isPresented: $confirmingFirstPairing, titleVisibility: .visible) {
                    Button(L("Pair now", "Şimdi eşleş")) { link.pair() }
                    Button(L("Cancel", "Vazgeç"), role: .cancel) {}
                } message: {
                    Text(sendsPairingSetup
                         ? L("This creates HuaSideload's own pairing on the watch (you confirm it on the watch), then sends the setup with the Huawei account ID above. If the watch says the accounts don't match and offers a reset, do NOT reset: close the app and turn the setup off.",
                             "Bu, saatte HuaSideload'un kendi eşleşmesini oluşturur (saatte onaylarsın), sonra yukarıdaki Huawei hesap ID'siyle kurulumu gönderir. Saat hesapların eşleşmediğini söyleyip sıfırlamayı önerirse SIFIRLAMA: uygulamayı kapat ve kurulumu kapat.")
                         : L("This creates HuaSideload's own pairing on the watch (you confirm it on the watch).",
                             "Bu, saatte HuaSideload'un kendi eşleşmesini oluşturur (saatte onaylarsın)."))
                }
                if !filmMode {
                    Toggle(L("Send setup after pairing (newer watches)", "Eşleşmeden sonra kurulum gönder (yeni saatler)"), isOn: $sendsPairingSetup)
                    if sendsPairingSetup {
                        Label(L("For a watch set up without Huawei Health (new or factory-reset: this sets it up, tested on a GT 3 SE) and for watches that report \"Pairing failed\" without it (e.g. Watch Fit 4 Pro). It tells the watch which Huawei account it belongs to: on a watch set up with Huawei Health, an empty or wrong account ID makes the watch say \"phone and watch accounts don't match\" and offer a factory reset. Never tap Reset on the watch; close the app and turn this off.",
                                "Huawei Health olmadan kurulan saat için (yeni ya da sıfırlanmış: saati bununla kurar, GT 3 SE'de denendi) ve bu olmadan \"Eşleşme başarısız\" diyen saatler için (ör. Watch Fit 4 Pro). Saate hangi Huawei hesabına ait olduğunu söyler: Huawei Health ile kurulmuş saatte boş ya da yanlış hesap ID'si saate \"telefon ve saat hesapları eşleşmiyor\" dedirtir ve fabrika ayarlarına sıfırlamayı önerir. Saatte asla Sıfırla'ya basma; uygulamayı kapat ve bunu kapat."),
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                        SecureField(L("Huawei account ID (empty: no account)", "Huawei hesap ID'si (boş: hesap yok)"), text: $huaweiAccountId)
                            .keyboardType(.numberPad)
                            .onChange(of: huaweiAccountId) { _, value in
                                CredentialStore.shared.set(value.trimmingCharacters(in: .whitespacesAndNewlines), for: CredentialStore.huaweiAccountKey)
                            }
                    }
                }
            } else if !filmMode {
                Button(L("Refresh battery and watch info", "Pil ve saat bilgisini yenile")) { link.refresh() }
                    .disabled(link.busy != nil)
            }
            Button(L("Disconnect (release for Huawei Health)", "Bağlantıyı kes (Huawei Health'e bırak)"), role: .destructive) { link.disconnect() }
        } header: {
            Text(L("Watch", "Saat"))
        } footer: {
            if link.isPaired && !filmMode {
                Text(L("To go back to Huawei Health: tap Disconnect, then open Huawei Health. Disconnecting keeps the watch's data, its Huawei Health pairing and HuaSideload's saved key; it is not Forget pairing and not a reset.",
                       "Huawei Health'e dönmek için: Bağlantıyı kes'e dokun, sonra Huawei Health'i aç. Bağlantıyı kesmek saatin verilerini, Huawei Health eşleşmesini ve HuaSideload'un kayıtlı anahtarını korur; eşleşmeyi unutmak ya da sıfırlamak değildir."))
            } else if !link.isPaired && !link.hasSavedPairing && !filmMode {
                Text(L("Close Huawei Health before pairing (swipe it up in the app switcher). The watch may ask for confirmation the first time. A watch set up with Huawei Health may still be tied to that Huawei account: if it reports \"Pairing failed\", turn on \"Send setup after pairing\", enter the account ID (the userId cookie on cloud.huawei.com, see Gadgetbridge's Huawei pairing guide) and pair again.",
                       "Eşleşmeden önce Huawei Health'i kapat (uygulama değiştiriciden yukarı kaydır). İlk eşleşmede saatin ekranında onay çıkabilir. Huawei Health ile kurulan saat o Huawei hesabına bağlı kalabilir: saat \"Eşleşme başarısız\" derse \"Eşleşmeden sonra kurulum gönder\"i aç, hesap ID'sini gir (cloud.huawei.com'daki userId çerezi, Gadgetbridge'in Huawei eşleşme rehberine bak) ve tekrar eşleş."))
            }
        }
    }

    private var notificationSection: some View {
        Section(L("Send a notification to the watch", "Saate bildirim gönder")) {
            TextField(L("Message", "Mesaj"), text: $message, axis: .vertical)
                .lineLimit(1...4)
                .focused($messageFocused)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(L("Done", "Bitti")) { messageFocused = false }
                    }
                }
            Button(L("Send", "Gönder")) {
                messageFocused = false
                link.sendMessage(message)
            }
                .disabled(link.busy != nil || message.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var logSection: some View {
        Section {
            Toggle(L("Pairing diagnostics (no keys)", "Eşleşme tanılaması (anahtarsız)"), isOn: $pairingDiagnostics)
            ForEach(link.log.reversed()) { LogRow(entry: $0, text: link.display($0.text)) }
        } header: {
            HStack {
                Text(L("Log (newest first)", "Log (en yeni üstte)"))
                Spacer()
                Button(L("Clear", "Temizle"), systemImage: "trash") { link.clearLog() }
                    .labelStyle(.iconOnly)
                    .disabled(link.log.isEmpty)
                if !filmMode {
                Button(copied ? L("Copied", "Kopyalandı") : L("Copy", "Kopyala")) {
                    UIPasteboard.general.string = link.logText
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                }
                ShareLink(item: link.logText) { Image(systemName: "square.and.arrow.up") }
                }
            }
            .textCase(nil)
        }
    }
}

private struct DeviceRow: View {
    let device: FoundDevice

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .fontWeight(device.looksHuawei ? .semibold : .regular)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    if device.looksHuawei { Text("Huawei").foregroundStyle(.orange) }
                    if device.systemConnected { Text(L("connected to phone", "telefona bağlı")).foregroundStyle(.green) }
                }
                .font(.caption)
            }
            Spacer()
            if let rssi = device.rssi {
                Text("\(rssi) dBm").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct LogRow: View {
    let entry: LogEntry
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(color)
            .textSelection(.enabled)
    }

    private var color: Color {
        switch entry.kind {
        case .info: return .primary
        case .sent: return .blue
        case .received: return .purple
        case .success: return .green
        case .error: return .red
        }
    }
}
