import SwiftUI

// Install tab → Watch faces → On the watch: lists the faces on the watch and deletes them (frees slots when the
// watch reports "too many watch faces", error 0x222E4)
struct WatchFacesOnWatchView: View {
    @ObservedObject var link: WatchLink
    @State private var pendingDelete: WatchFaceService.Installed?

    var body: some View {
        List {
            if let status = link.faceListStatus {
                Section {
                    StatusCard(state: StatusCard.State(status.ok), title: status.text, detail: status.hint)
                }
            }
            Section {
                if !link.watchFacesLoaded {
                    HStack { ProgressView(); Text(L("Reading the watch faces…", "Kadranlar okunuyor…")).foregroundStyle(.secondary) }
                } else if link.watchFacesOnWatch.isEmpty {
                    Text(L("The watch listed no watch faces.", "Saat hiç kadran listelemedi.")).foregroundStyle(.secondary)
                } else {
                    ForEach(link.watchFacesOnWatch, id: \.name) { face in
                        row(face)
                    }
                }
            } header: {
                Text(link.watchFacesLoaded ? L("On the watch (\(link.watchFacesOnWatch.count))", "Saatte (\(link.watchFacesOnWatch.count))")
                                           : L("On the watch", "Saatte"))
            } footer: {
                Text(L("Deleting frees a slot when the watch says it has too many watch faces. The face in use can't be deleted: switch to another one on the watch first. Built-in faces may refuse to be deleted.",
                       "Saat çok fazla kadran olduğunu söylediğinde silmek yer açar. Kullanılan kadran silinemez: önce saatte başka birine geç. Yerleşik kadranlar silinmeyi reddedebilir."))
            }
        }
        .navigationTitle(L("Watch faces on the watch", "Saatteki kadranlar"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { link.loadWatchFacesOnWatch() } label: { Image(systemName: "arrow.clockwise") }
                .disabled(link.busy != nil)
                .accessibilityLabel(L("Refresh", "Yenile"))
        }
        .task { if !link.watchFacesLoaded { link.loadWatchFacesOnWatch() } }
        .confirmationDialog(L("Delete this watch face?", "Bu kadran silinsin mi?"),
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { face in
            Button(L("Delete \(link.watchFaceTitle(face))", "\(link.watchFaceTitle(face)) sil"), role: .destructive) {
                link.deleteWatchFace(face)
            }
            Button(L("Cancel", "Vazgeç"), role: .cancel) {}
        } message: { _ in
            Text(L("It is removed from the watch. To get it back you install it again.",
                   "Saatten kaldırılır. Geri istersen tekrar kurman gerekir."))
        }
    }

    private func row(_ face: WatchFaceService.Installed) -> some View {
        HStack(spacing: 12) {
            Image(systemName: face.isCurrent ? "clock.fill" : "clock")
                .font(.title3)
                .foregroundStyle(face.isCurrent ? Color.accentColor : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(link.watchFaceTitle(face)).lineLimit(1)
                Text(details(face)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if link.deletingFace == face.fileName {
                ProgressView()
            } else if !face.isCurrent {
                Button(role: .destructive) { pendingDelete = face } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .disabled(link.busy != nil)
                    .accessibilityLabel(L("Delete", "Sil"))
            }
        }
        .padding(.vertical, 2)
    }

    private func details(_ face: WatchFaceService.Installed) -> String {
        var parts: [String] = []
        if face.isCurrent { parts.append(L("In use", "Kullanılıyor")) }
        if face.isFactory { parts.append(L("Built-in", "Yerleşik")) }
        if link.watchFaceTitles[face.name] != nil { parts.append(face.name) }
        if !face.version.isEmpty { parts.append(face.version) }
        return parts.joined(separator: " · ")
    }
}
