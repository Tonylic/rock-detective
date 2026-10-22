import SwiftUI

@main
struct RockDetectiveApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.loadReferenceGallery() }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .identify:
                        if let session = model.activeSession {
                            IdentifyView(session: session)
                        }
                    case .rock(let id):
                        if let rock = model.catalog.rock(id: id) {
                            RockDetailView(rock: rock)
                        }
                    case .collection:
                        CollectionView()
                    case .rockBook:
                        RockBookView()
                    case .rockCycle:
                        RockCycleView()
                    }
                }
        }
        .tint(Theme.lava)
        .fullScreenCover(item: $model.pendingPhoto) { pending in
            PhotoCropView(photo: pending.image) { cropped in
                model.useFramedPhoto(cropped)
            } onCancel: {
                model.cancelFraming()
            }
        }
    }
}
