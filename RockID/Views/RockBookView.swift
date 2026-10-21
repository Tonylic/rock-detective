import RockKit
import SwiftUI

/// All rocks, grouped by family, with the ones the kid has found starred.
struct RockBookView: View {
    @Environment(AppModel.self) private var model
    @State private var filter: RockFamily?

    private var rocks: [Rock] {
        guard let filter else { return model.catalog.rocks }
        return model.catalog.rocks(in: filter)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                NavigationLink(value: Route.rockCycle) {
                    HStack(spacing: 16) {
                        Text("♻️").font(.system(size: 44))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("The Rock Cycle")
                                .font(Theme.rounded(26, weight: .heavy))
                            Text("How rocks change from one kind into another")
                                .font(Theme.rounded(17, weight: .medium))
                                .opacity(0.9)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.title2.bold())
                    }
                    .padding(22)
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.sunshine, foreground: Color(hex: 0x3A2E25)))
                .accessibilityIdentifier("rockCycleButton")

                Picker("Rock family", selection: $filter) {
                    Text("All").tag(RockFamily?.none)
                    ForEach(RockFamily.allCases) { family in
                        Text("\(family.emoji) \(family.displayName)").tag(RockFamily?.some(family))
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.large)

                if let filter {
                    Text("\(filter.emoji) \(filter.kidExplanation)")
                        .font(Theme.rounded(19, weight: .semibold))
                        .foregroundStyle(Theme.color(for: filter))
                        .fixedSize(horizontal: false, vertical: true)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 18)], spacing: 18) {
                    ForEach(rocks) { rock in
                        NavigationLink(value: Route.rock(rock.id)) {
                            RockBookCard(rock: rock, discovered: model.store.discoveredRockIDs.contains(rock.id))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("rockCard_\(rock.id)")
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Rock Book")
    }
}

struct RockBookCard: View {
    let rock: Rock
    let discovered: Bool

    var body: some View {
        VStack(spacing: 8) {
            RockArtView(rock: rock, size: 120)
            Text(rock.name)
                .font(Theme.rounded(21, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            FamilyBadge(family: rock.family)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if discovered {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.sunshine)
                    .padding(10)
                    .accessibilityLabel("Found")
            }
        }
        .shadow(color: .black.opacity(0.08), radius: 10, y: 5)
        .accessibilityElement(children: .combine)
    }
}
