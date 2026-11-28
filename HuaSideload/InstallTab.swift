import SwiftUI
import UIKit

// The Install tab: watch apps (ready to install and on the watch), watch faces and music for the watch's player.
// Every row has one clear action; a status card on top of each section follows what is running.
struct InstallTab: View {
    @ObservedObject var link: WatchLink
    let filmMode: Bool
    // Apps a feature hides while filming (WatchFeature.filmModeHiddenApps)
    let hiddenApps: Set<String>

    @AppStorage(WatchFaceUploadMethod.storageKey) private var faceUploadMethod = WatchFaceUploadMethod.bin.rawValue
    @State private var pickingApp = false
    @State private var pickingFace = false
    @State private var pickingMusic = false
    @State private var appToRemove: WatchApps.Installed?
    @State private var removingByName = false
    @State private var packageToRemove = ""

    private static let developerGuide = URL(string: "https://github.com/burak4arslan/huawei-watch-sideload-ios/blob/main/docs/DEVELOPMENT.md#3-things-to-know-when-writing-watch-apps")!

    var body: some View {
        Group {
            appsSection
            installedSection
            facesSection
            if !filmMode { musicSection }
        }
    }

    // MARK: - Watch apps ready to install

    private var readyApps: [BundledWatchApp] {
        (WatchAppCatalog.all + link.importedApps).filter { !filmMode || !hiddenApps.contains($0.name) }
    }

    private var appsSection: some View {
        Section {
            if let status = link.appInstallStatus {
                StatusCard(state: StatusCard.State(status.ok), title: status.text, detail: status.hint,
                           progress: link.installingPackage != nil ? link.watchAppProgress : nil,
                           help: status.ok == false && status.hint != nil && !filmMode ? Self.developerGuide : nil)
            }
            ForEach(readyApps) { app in
                ReadyAppRow(app: app,
                            onWatch: link.installedAppsLoaded ? link.installedApps.first { $0.package == app.package } : nil,
                            installing: link.installingPackage == app.package,
                            progress: link.watchAppProgress,
                            disabled: link.busy != nil) {
                    link.installWatchApp(app)
                }
                .swipeActions {
                    if app.imported && !filmMode {
                        Button(L("Remove from list", "Listeden çıkar"), role: .destructive) { link.forgetImportedApp(app) }
                    }
                }
            }
            if !filmMode {
                Button { pickingApp = true } label: {
                    Label(L("Install from Files (.bin)…", "Dosyalardan kur (.bin)…"), systemImage: "doc.badge.plus")
                }
                .disabled(link.busy != nil)
            }
        } header: {
            Text(L("Watch apps", "Saat uygulamaları"))
        } footer: {
            if !filmMode {
                Text(readyApps.isEmpty
                     ? L("Pick a signed watch app (.bin, built with tools/build-watch-app.sh). It stays in this list for later installs; swipe left to take it off.",
                         "İmzalı bir saat uygulaması seç (.bin, tools/build-watch-app.sh ile derlenir). Sonraki kurulumlar için bu listede kalır; çıkarmak için sola kaydır.")
                     : L("Apps added from Files stay in this list; swipe left to take one off.",
                         "Dosyalardan eklenen uygulamalar bu listede kalır; çıkarmak için sola kaydır."))
            }
        }
        .fileImporter(isPresented: $pickingApp, allowedContentTypes: [.data]) { result in
            if case .success(let url) = result { link.importWatchApp(url) }
        }
    }

    // MARK: - Apps on the watch

    private var installedSection: some View {
        Section {
            if !link.installedAppsLoaded {
                Button { link.loadInstalledApps() } label: {
                    Label(L("Read the list from the watch", "Listeyi saatten oku"), systemImage: "arrow.down.circle")
                }
                .disabled(link.busy != nil)
            } else if link.installedApps.isEmpty {
                Text(L("No apps installed from a phone", "Telefondan kurulmuş uygulama yok"))
                    .foregroundStyle(.secondary)
            }
            ForEach(link.installedApps) { app in
                InstalledAppRow(app: app, icon: WatchAppIcons.image(forPackage: app.package, in: WatchAppCatalog.all + link.importedApps),
                                removing: link.removingPackage == app.package, disabled: link.busy != nil) {
                    appToRemove = app
                }
                .swipeActions {
                    Button(L("Remove", "Kaldır"), role: .destructive) { appToRemove = app }
                }
            }
            if !filmMode {
                Button { packageToRemove = ""; removingByName = true } label: {
                    Label(L("Remove by package name…", "Paket adıyla kaldır…"), systemImage: "minus.circle")
                }
                .disabled(link.busy != nil)
            }
        } header: {
            HStack {
                Text(L("On the watch", "Saatte kurulu"))
                Spacer()
                Button { link.loadInstalledApps() } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(link.busy != nil)
                    .accessibilityLabel(L("Refresh", "Yenile"))
            }
        } footer: {
            if !filmMode {
                Text(L("If an app doesn't show up here, remove it by its package name (bundleName in its config.json).",
                       "Bir uygulama burada görünmüyorsa paket adıyla kaldır (config.json'daki bundleName)."))
            }
        }
        .task(id: link.isPaired) { link.loadInstalledAppsOnce() }
        .confirmationDialog(L("Remove this app from the watch?", "Bu uygulama saatten kaldırılsın mı?"),
                            isPresented: Binding(get: { appToRemove != nil }, set: { if !$0 { appToRemove = nil } }),
                            titleVisibility: .visible, presenting: appToRemove) { app in
            Button(L("Remove \(app.displayName)", "\(app.displayName) uygulamasını kaldır"), role: .destructive) {
                link.deleteWatchApp(package: app.package, name: app.name)
            }
            Button(L("Cancel", "Vazgeç"), role: .cancel) {}
        } message: { app in
            Text(L("\(app.package) and its data are deleted from the watch.", "\(app.package) ve verileri saatten silinir."))
        }
        .alert(L("Remove by package name", "Paket adıyla kaldır"), isPresented: $removingByName) {
            TextField("com.example.myapp", text: $packageToRemove)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button(L("Remove", "Kaldır"), role: .destructive) { link.deleteWatchApp(package: packageToRemove) }
            Button(L("Cancel", "Vazgeç"), role: .cancel) {}
        } message: {
            Text(L("The watch app's package name, e.g. com.yourname.myapp. Its data on the watch is deleted too.",
                   "Saat uygulamasının paket adı, ör. com.adin.uygulaman. Saatteki verileri de silinir."))
        }
    }

    // MARK: - Watch faces

    private var faceState: StatusCard.State {
        switch link.watchFaceStage {
        case .failed: return .failed
        case .installed, .active: return .done
        default: return .working
        }
    }

    private var facesSection: some View {
        Section {
            if link.watchFaceStage != .idle, let status = link.watchFaceStatus {
                StatusCard(state: faceState, title: status,
                           detail: link.watchFaceCompatibility?.label,
                           progress: isTransferring ? link.watchAppProgress : nil)
            }
            ForEach(WatchFaceCatalog.all, id: \.self) { url in
                let compatibility = WatchFaceCompatibility.evaluate(screenCode: WatchFaceCatalog.screens[url] ?? "?", device: link.watchFaceParams)
                FaceRow(name: url.deletingPathExtension().lastPathComponent,
                        cover: WatchFaceCatalog.cover(url),
                        screen: WatchFaceCatalog.screens[url].flatMap { WatchFaceScreen.resolutions[$0] },
                        compatibility: link.watchFaceParams == nil ? nil : compatibility,
                        disabled: link.busy != nil || compatibility.blocksInstall) {
                    link.installWatchFace(url, title: url.deletingPathExtension().lastPathComponent)
                }
            }
            if !filmMode {
                Button { pickingFace = true } label: {
                    Label(L("Install from Files (.hwt)…", "Dosyalardan kur (.hwt)…"), systemImage: "doc.badge.plus")
                }
                .disabled(link.busy != nil)
                NavigationLink {
                    WatchFacesOnWatchView(link: link)
                } label: {
                    Label(L("Watch faces on the watch", "Saatteki kadranlar"), systemImage: "square.stack")
                }
                .disabled(link.busy != nil)
                NavigationLink {
                    UploadMethodPicker(selection: $faceUploadMethod)
                } label: {
                    LabeledContent(L("Upload method", "Yükleme yöntemi"),
                                   value: (WatchFaceUploadMethod(rawValue: faceUploadMethod) ?? .bin).shortTitle)
                }
                .disabled(link.busy != nil)
            }
        } header: {
            Text(L("Watch faces", "Kadranlar"))
        } footer: {
            if !filmMode {
                Text(L("Faces made with Huawei Theme Studio (.hwt). The app checks the face's screen against the watch first. After the install, touch and hold the watch face on the watch and pick the new one.",
                       "Huawei Theme Studio ile yapılan kadranlar (.hwt). Uygulama önce kadranın ekranını saatle karşılaştırır. Kurulumdan sonra saatte kadrana basılı tut ve yenisini seç."))
            }
        }
        .fileImporter(isPresented: $pickingFace, allowedContentTypes: [.data]) { result in
            if case .success(let url) = result { link.installWatchFace(url) }
        }
    }

    private var isTransferring: Bool {
        if case .transferring = link.watchFaceStage { return true }
        return false
    }

    // MARK: - Music

    private var musicSection: some View {
        Section {
            if let status = link.musicUploadStatus {
                StatusCard(state: .working, title: L("Uploading music", "Müzik yükleniyor"), detail: status, progress: link.watchAppProgress)
            }
            Button { pickingMusic = true } label: {
                Label(L("Add songs from Files…", "Dosyalardan şarkı ekle…"), systemImage: "music.note.list")
            }
            .disabled(link.busy != nil)
            if let storage = link.musicStorage {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(L("Songs on the watch", "Saatteki şarkılar"))
                        Spacer()
                        Text("\(storage.songs) / \(storage.maxSongs)").foregroundStyle(.secondary).monospacedDigit()
                    }
                    ProgressView(value: Double(min(storage.songs, storage.maxSongs)), total: Double(max(storage.maxSongs, 1)))
                    Text(L("\(storage.freeMB) MB free", "\(storage.freeMB) MB boş")).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } else {
                Button { link.loadMusicStorage() } label: {
                    Label(L("Check the watch's storage", "Saatin hafızasını kontrol et"), systemImage: "internaldrive")
                }
                .disabled(link.busy != nil)
            }
        } header: {
            HStack {
                Text(L("Music for the watch", "Saat için müzik"))
                Spacer()
                if link.musicStorage != nil {
                    Button { link.loadMusicStorage() } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(link.busy != nil)
                        .accessibilityLabel(L("Refresh", "Yenile"))
                }
            }
        } footer: {
            Text(L("MP3, M4A, AAC, FLAC, WAV or OPUS. Songs play from the watch's own Music app without the phone. DRM-protected songs (Spotify, Apple Music) can't be uploaded.",
                   "MP3, M4A, AAC, FLAC, WAV ya da OPUS. Şarkılar saatin kendi Müzik uygulamasından telefonsuz çalar. DRM'li şarkılar (Spotify, Apple Music) yüklenemez."))
        }
        .fileImporter(isPresented: $pickingMusic, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { link.uploadMusic(urls) }
        }
    }
}

// MARK: - Rows

private struct ReadyAppRow: View {
    let app: BundledWatchApp
    let onWatch: WatchApps.Installed?
    let installing: Bool
    let progress: Double?
    let disabled: Bool
    let install: () -> Void

    // The watch refuses the same or a lower version (103), so only a newer build gets a button
    private enum Comparison { case notInstalled, same, newer, older }
    private var comparison: Comparison {
        guard let onWatch else { return .notInstalled }
        switch app.version.compare(onWatch.version, options: .numeric) {
        case .orderedSame: return .same
        case .orderedDescending: return .newer
        case .orderedAscending: return .older
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            AppBadge(name: app.name, seed: app.package, image: WatchAppIcons.image(for: app))
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.body.weight(.semibold)).lineLimit(1)
                Text([app.version.isEmpty ? nil : app.version, "\(max(app.data.count / 1024, 1)) KB",
                      app.imported ? L("from Files", "dosyadan") : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                switch comparison {
                case .same:
                    note(L("On the watch", "Saatte kurulu"), icon: "checkmark.circle.fill", color: .green)
                case .newer:
                    note(L("On the watch: \(onWatch?.version ?? "")", "Saatteki: \(onWatch?.version ?? "")"), icon: "arrow.up.circle.fill", color: .orange)
                case .older:
                    note(L("Newer on the watch: \(onWatch?.version ?? "")", "Saattekisi daha yeni: \(onWatch?.version ?? "")"), icon: "checkmark.circle", color: .secondary)
                case .notInstalled:
                    EmptyView()
                }
            }
            Spacer(minLength: 8)
            if installing {
                ProgressRing(value: progress ?? 0)
            } else {
                switch comparison {
                case .notInstalled, .newer:
                    Button(comparison == .newer ? L("Update", "Güncelle") : L("Install", "Kur"), action: install)
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .disabled(disabled)
                case .same, .older:
                    EmptyView()
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func note(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(color)
    }
}

private struct InstalledAppRow: View {
    let app: WatchApps.Installed
    let icon: UIImage?
    let removing: Bool
    let disabled: Bool
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AppBadge(name: app.displayName, seed: app.package, image: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName).lineLimit(1)
                Text([app.package, app.version].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if removing {
                ProgressView()
            } else {
                Button(role: .destructive, action: remove) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .disabled(disabled)
                    .accessibilityLabel(L("Remove", "Kaldır"))
            }
        }
        .padding(.vertical, 2)
    }
}

private struct FaceRow: View {
    let name: String
    let cover: UIImage?
    let screen: String?
    let compatibility: WatchFaceCompatibility?
    let disabled: Bool
    let install: () -> Void

    private var caption: (text: String, color: Color) {
        let size = screen.map { $0.replacingOccurrences(of: "*", with: "×") }
        switch compatibility {
        case .compatible: return (L("Fits this watch", "Bu saate uygun") + (size.map { " · \($0)" } ?? ""), .green)
        case .incompatible: return (L("Made for \(size ?? "?"), not this watch", "\(size ?? "?") için, bu saate uygun değil"), .red)
        case .unknown, nil: return (size.map { L("Made for \($0)", "\($0) için") } ?? L("Screen unknown", "Ekran bilinmiyor"), .secondary)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let cover {
                    Image(uiImage: cover).resizable().scaledToFill()
                } else {
                    Image(systemName: "applewatch.watchface").font(.title3).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.secondarySystemFill))
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.quaternary, lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body.weight(.semibold)).lineLimit(1)
                Text(caption.text).font(.caption).foregroundStyle(caption.color)
            }
            Spacer(minLength: 8)
            Button(L("Install", "Kur"), action: install)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .disabled(disabled)
        }
        .padding(.vertical, 2)
    }
}

// The app's own launcher icon; without one, a round badge with its initial in a color derived from its package
private struct AppBadge: View {
    let name: String
    let seed: String
    let image: UIImage?

    private var hue: Double {
        let hash = seed.unicodeScalars.reduce(UInt32(2166136261)) { ($0 ^ $1.value) &* 16777619 }
        return Double(hash % 360) / 360
    }

    var body: some View {
        Group {
            if let image {
                // Watch launcher icons are round; clip so a square one looks the same as on the watch
                Image(uiImage: image).resizable().interpolation(.high).scaledToFit().clipShape(Circle())
            } else {
                Circle()
                    .fill(LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.95),
                                                  Color(hue: hue, saturation: 0.8, brightness: 0.7)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Text(String(name.first ?? "?").uppercased()).font(.headline.weight(.bold)).foregroundStyle(.white))
            }
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }
}

private struct ProgressRing: View {
    let value: Double

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 3)
            Circle().trim(from: 0, to: max(0.02, min(value, 1)))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: value)
        }
        .frame(width: 26, height: 26)
        .accessibilityLabel(L("\(Int(value * 100)) percent", "Yüzde \(Int(value * 100))"))
    }
}

// What is running in a section, or how it ended
struct StatusCard: View {
    enum State {
        case working, done, failed

        init(_ ok: Bool?) { self = ok == nil ? .working : (ok! ? .done : .failed) }
    }

    let state: State
    let title: String
    var detail: String? = nil
    var progress: Double? = nil
    var help: URL? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                switch state {
                case .working: ProgressView()
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }
            .font(.title3)
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold))
                if let progress {
                    HStack(spacing: 8) {
                        ProgressView(value: min(max(progress, 0), 1))
                        Text("\(Int(progress * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                if let help {
                    Link(L("Developer guide: install errors", "Geliştirici kılavuzu: kurulum hataları"), destination: help)
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// The four ways to send a watch face; only worth changing when a face transfers but never shows up
private struct UploadMethodPicker: View {
    @Binding var selection: String

    var body: some View {
        List {
            Section {
                ForEach(WatchFaceUploadMethod.allCases) { method in
                    Button { selection = method.rawValue } label: {
                        HStack {
                            Text(method.label).foregroundStyle(.primary)
                            Spacer()
                            if selection == method.rawValue {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor).fontWeight(.semibold)
                            }
                        }
                    }
                }
            } footer: {
                Text(L("A works on most watches. Try another one only if a face transfers but never shows up on the watch; full HarmonyOS watches may want the whole package (C or D).",
                       "A çoğu saatte çalışır. Başkasını sadece kadran aktarıldığı hâlde saatte hiç görünmüyorsa dene; tam HarmonyOS saatler bütün paketi isteyebilir (C ya da D)."))
            }
        }
        .navigationTitle(L("Upload method", "Yükleme yöntemi"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension WatchApps.Installed {
    var displayName: String { name.isEmpty ? package : name }
}

extension WatchFaceUploadMethod {
    var shortTitle: String { shortLabel + (self == .bin ? L(" (standard)", " (standart)") : "") }
}

extension WatchFaceCatalog {
    // preview/cover.jpg of each bundled face, read once
    private static let covers: [URL: UIImage] = Dictionary(uniqueKeysWithValues: all.compactMap { url in
        guard let data = try? Data(contentsOf: url), let zip = try? ZipArchive([UInt8](data)),
              let jpeg = zip.file("preview/cover.jpg"), let image = UIImage(data: Data(jpeg)) else { return nil }
        return (url, image)
    })

    static func cover(_ url: URL) -> UIImage? { covers[url] }
}

// Launcher icons of watch apps (BundledWatchApp.icon), decoded once per package build
enum WatchAppIcons {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for app: BundledWatchApp) -> UIImage? {
        guard let bytes = app.icon else { return nil }
        let key = "\(app.id)|\(app.version)|\(app.data.count)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = decode(bytes) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    // An app on the watch shows the icon of the same package when the phone has it (built in or from Files)
    static func image(forPackage package: String, in apps: [BundledWatchApp]) -> UIImage? {
        apps.last { $0.package == package && $0.icon != nil }.flatMap(image(for:))
    }

    private static func decode(_ bytes: [UInt8]) -> UIImage? {
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return UIImage(data: Data(bytes)) }
        // Converted image (icon.bin): 4-byte header, width and height as LE16, then BGRA pixels
        guard bytes.count > 8 else { return nil }
        let width = Int(bytes[4]) | Int(bytes[5]) << 8, height = Int(bytes[6]) | Int(bytes[7]) << 8
        guard width > 0, height > 0, bytes.count == 8 + width * height * 4,
              let provider = CGDataProvider(data: Data(bytes[8...]) as CFData),
              let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.first.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
