import PhotosUI
import RockKit
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var isLoadingPhoto = false
    @State private var photoError = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                photoButtons
                tipsCard
                destinations
                progressCard
            }
            .padding(32)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                model.startIdentification(with: image)
            } onCancel: {
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickerItem, matching: .images, photoLibrary: .shared())
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadPickedPhoto(item) }
        }
        .alert("Oops! That photo didn't work.", isPresented: $photoError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try picking a different photo of your rock.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 8) {
            MascotView(size: 150)
            Text("Rock Detective")
                .font(Theme.rounded(56, weight: .black))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("appTitle")
            Text("Snap a rock. Find the clues. Crack the case!")
                .font(Theme.rounded(22, weight: .semibold))
                .foregroundStyle(Theme.subtleInk)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    private var photoButtons: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                if CameraPicker.isAvailable {
                    Button {
                        showCamera = true
                    } label: {
                        bigButtonLabel(emoji: "📷", title: "Take a Photo", subtitle: "Use the camera")
                    }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.lava))
                    .accessibilityIdentifier("takePhotoButton")
                }

                Button {
                    showPhotoPicker = true
                } label: {
                    bigButtonLabel(emoji: "🖼️", title: "Choose a Photo", subtitle: "From your pictures")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.sky))
                .accessibilityIdentifier("choosePhotoButton")
            }

            if let rock = model.practiceRock {
                Button {
                    model.startPractice()
                } label: {
                    Text("🧪 Practice Rock (\(rock.name))")
                        .font(Theme.rounded(20, weight: .bold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.grape))
                .accessibilityIdentifier("practiceRockButton")
            }

            if isLoadingPhoto {
                ProgressView("Opening your photo…")
                    .font(Theme.rounded(18))
            }
        }
    }

    private func bigButtonLabel(emoji: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(emoji).font(.system(size: 60))
            Text(title).font(Theme.rounded(30, weight: .heavy))
            Text(subtitle).font(Theme.rounded(17, weight: .medium)).opacity(0.9)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(.horizontal, 12)
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(emoji: "💡", text: "Photo tips")
            FlowLayout(spacing: 10) {
                Chip(emoji: "🔍", text: "Get close so the rock fills the picture")
                Chip(emoji: "☀️", text: "Use bright light, no flash glare")
                Chip(emoji: "💧", text: "A wet rock shows its colors better")
                Chip(emoji: "🧼", text: "Brush off dirt first")
            }
        }
        .card()
    }

    private var destinations: some View {
        HStack(spacing: 20) {
            NavigationLink(value: Route.collection) {
                destinationLabel(
                    emoji: "🧺",
                    title: "My Rocks",
                    detail: model.store.findings.isEmpty
                        ? "Your collection is waiting!"
                        : "\(model.store.findings.count) rock find\(model.store.findings.count == 1 ? "" : "s")",
                    color: Theme.ocean
                )
            }
            .buttonStyle(ChunkyButtonStyle(color: Theme.ocean))
            .accessibilityIdentifier("myRocksButton")

            NavigationLink(value: Route.rockBook) {
                destinationLabel(
                    emoji: "📖",
                    title: "Rock Book",
                    detail: "Meet all \(model.catalog.rocks.count) rocks",
                    color: Theme.grape
                )
            }
            .buttonStyle(ChunkyButtonStyle(color: Theme.grape))
            .accessibilityIdentifier("rockBookButton")
        }
    }

    private func destinationLabel(emoji: String, title: String, detail: String, color: Color) -> some View {
        HStack(spacing: 16) {
            Text(emoji).font(.system(size: 48))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.rounded(28, weight: .heavy))
                Text(detail).font(Theme.rounded(17, weight: .medium)).opacity(0.92)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.title2.bold())
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var progressCard: some View {
        let found = model.store.discoveredRockIDs.count
        let total = model.catalog.rocks.count
        return VStack(alignment: .leading, spacing: 12) {
            CardTitle(emoji: "🏆", text: "Discoveries")
            Text(found == 0
                 ? "Identify your first rock to start your discovery list!"
                 : "You've discovered \(found) of \(total) kinds of rocks!")
                .font(Theme.rounded(20, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier("discoveryText")
            ProgressView(value: Double(found), total: Double(total))
                .tint(Theme.sunshine)
                .scaleEffect(x: 1, y: 2.5, anchor: .center)
                .padding(.vertical, 6)
        }
        .card()
    }

    // MARK: - Actions

    private func loadPickedPhoto(_ item: PhotosPickerItem) async {
        isLoadingPhoto = true
        defer {
            isLoadingPhoto = false
            pickerItem = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            photoError = true
            return
        }
        let image = await Task.detached(priority: .userInitiated) {
            try? ImageLoader.image(from: data, maxPixelSize: 2048)
        }.value
        guard let image else {
            photoError = true
            return
        }
        model.startIdentification(with: image)
    }
}
