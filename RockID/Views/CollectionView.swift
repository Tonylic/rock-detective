import RockKit
import SwiftUI

/// The kid's saved rock finds.
struct CollectionView: View {
    @Environment(AppModel.self) private var model
    @State private var isEditing = false
    @State private var pendingDelete: Finding?

    var body: some View {
        ScrollView {
            if model.store.findings.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 20)], spacing: 20) {
                    ForEach(model.store.findings) { finding in
                        FindingCard(finding: finding, isEditing: isEditing) {
                            pendingDelete = finding
                        }
                        .onTapGesture {
                            guard !isEditing else { return }
                            model.reopen(finding)
                        }
                        .accessibilityAddTraits(.isButton)
                    }
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("My Rocks")
        .toolbar {
            if !model.store.findings.isEmpty {
                Button(isEditing ? "Done" : "Edit") {
                    withAnimation { isEditing.toggle() }
                }
                .font(Theme.rounded(18, weight: .bold))
                .accessibilityIdentifier("editCollectionButton")
            }
        }
        .alert("Remove this rock?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { finding in
            Button("Remove", role: .destructive) {
                withAnimation { try? model.store.delete(id: finding.id) }
                if model.store.findings.isEmpty { isEditing = false }
            }
            Button("Keep it", role: .cancel) {}
        } message: { _ in
            Text("It will be taken out of My Rocks.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            MascotView(size: 140)
            Text("No rocks yet!")
                .font(Theme.rounded(40, weight: .black))
                .foregroundStyle(Theme.ink)
            Text("Find a rock, take its picture, and it will show up here.")
                .font(Theme.rounded(21, weight: .medium))
                .foregroundStyle(Theme.subtleInk)
                .multilineTextAlignment(.center)
        }
        .padding(60)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("emptyCollection")
    }
}

struct FindingCard: View {
    let finding: Finding
    let isEditing: Bool
    let onDelete: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let rock = model.catalog.rock(id: finding.bestRockID)
        VStack(alignment: .leading, spacing: 10) {
            ThumbnailView(url: model.store.photoURL(for: finding), fallbackRock: rock)
                .frame(height: 170)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text(finding.nickname ?? rock?.name ?? "Mystery rock")
                .font(Theme.rounded(24, weight: .heavy))
                .foregroundStyle(Theme.ink)
            HStack {
                if let rock { FamilyBadge(family: rock.family) }
                Spacer()
                StarsView(count: finding.level.stars, size: 16)
            }
            Text(finding.date.formatted(date: .abbreviated, time: .shortened))
                .font(Theme.rounded(14, weight: .medium))
                .foregroundStyle(Theme.subtleInk)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 5)
        .overlay(alignment: .topTrailing) {
            if isEditing {
                Button(action: onDelete) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 44))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Theme.lava)
                }
                .padding(6)
                .accessibilityLabel("Remove \(rock?.name ?? "rock")")
                .accessibilityIdentifier("deleteFindingButton")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("finding_\(finding.bestRockID)")
    }
}

/// Loads a saved photo off the main thread.
struct ThumbnailView: View {
    let url: URL?
    let fallbackRock: Rock?
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Theme.softCard
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else if let fallbackRock {
                RockArtView(rock: fallbackRock, size: 120)
            }
        }
        .task(id: url) {
            guard let url else { return }
            image = await Task.detached(priority: .utility) {
                guard let data = try? Data(contentsOf: url) else { return nil as CGImage? }
                return try? ImageLoader.image(from: data, maxPixelSize: 500)
            }.value
        }
    }
}
