import RockKit
import SwiftUI

/// Everything a kid can learn about one rock.
struct RockDetailView: View {
    let rock: Rock
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var familyColor: Color { Theme.color(for: rock.family) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                if let safety = rock.safetyNote {
                    Label(safety, systemImage: "exclamationmark.shield.fill")
                        .font(Theme.rounded(19, weight: .semibold))
                        .foregroundStyle(Theme.lava)
                        .card(padding: 18, fill: Theme.lava.opacity(0.12))
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    formedCard
                    mineralsCard
                    hardnessCard
                    whereCard
                    lookAlikeCard
                    rockCycleCard
                }
                funFactsCard
            }
            .padding(24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle(rock.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var columns: [GridItem] {
        sizeClass == .regular
            ? [GridItem(.flexible(), spacing: 20, alignment: .top), GridItem(.flexible(), spacing: 20, alignment: .top)]
            : [GridItem(.flexible())]
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 28) {
            RockArtView(rock: rock, size: sizeClass == .regular ? 220 : 150)
            VStack(alignment: .leading, spacing: 10) {
                Text(rock.name)
                    .font(Theme.rounded(54, weight: .black))
                    .foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.6)
                    .accessibilityIdentifier("rockDetailName")
                Text("Say it: \(rock.sayIt)")
                    .font(Theme.rounded(20, weight: .semibold))
                    .foregroundStyle(Theme.subtleInk)
                FamilyBadge(family: rock.family, large: true)
                    .accessibilityIdentifier("rockFamily")
                Text(rock.kind)
                    .font(Theme.rounded(17, weight: .medium))
                    .foregroundStyle(Theme.subtleInk)
                Text(rock.summary)
                    .font(Theme.rounded(21, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private var formedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(emoji: rock.family.emoji, text: "How it formed")
            Text(rock.formation)
                .font(Theme.rounded(18, weight: .medium))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(rock.family.displayName) rocks are \(rock.family.kidExplanation.prefix(1).lowercased() + rock.family.kidExplanation.dropFirst()) \(rock.family.nameMeaning)")
                .font(Theme.rounded(15, weight: .medium))
                .foregroundStyle(familyColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private var mineralsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(emoji: "🧪", text: "What it's made of")
            FlowLayout(spacing: 8) {
                ForEach(rock.minerals, id: \.self) { mineral in
                    Chip(emoji: "🔹", text: mineral)
                }
            }
        }
        .card()
    }

    private var hardnessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(emoji: "💪", text: "How hard is it?")
            Text("Mohs hardness \(rock.hardness.displayText)")
                .font(Theme.rounded(20, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier("hardnessText")
            HardnessScaleView(range: rock.hardness, color: familyColor)
            Text(rock.hardness.kidComparison)
                .font(Theme.rounded(16, weight: .medium))
                .foregroundStyle(Theme.subtleInk)
        }
        .card()
    }

    private var whereCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(emoji: "🗺️", text: "Where to find it")
            Text(rock.whereFound)
                .font(Theme.rounded(18, weight: .medium))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private var lookAlikeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(emoji: "👯", text: "Look-alikes")
            Text(rock.lookAlikeTip)
                .font(Theme.rounded(18, weight: .medium))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private var rockCycleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(emoji: "♻️", text: "Rock cycle")
            if rock.formsFrom.isEmpty && rock.canBecome.isEmpty {
                Text(rock.family == .igneous
                     ? "It's made straight from melted rock. Heat, pressure, or weathering can turn it into other rocks."
                     : "Weathering, heat, and pressure can slowly turn it into other rocks.")
                    .font(Theme.rounded(17, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !rock.formsFrom.isEmpty {
                linkRow(title: "Can form from", ids: rock.formsFrom)
            }
            if !rock.canBecome.isEmpty {
                linkRow(title: "Can turn into", ids: rock.canBecome)
            }
            NavigationLink(value: Route.rockCycle) {
                Label("See the rock cycle", systemImage: "arrow.triangle.2.circlepath")
                    .font(Theme.rounded(17, weight: .bold))
            }
        }
        .card()
    }

    private func linkRow(title: String, ids: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.rounded(16, weight: .bold))
                .foregroundStyle(Theme.subtleInk)
            FlowLayout(spacing: 8) {
                ForEach(ids, id: \.self) { id in
                    if let other = model.catalog.rock(id: id) {
                        NavigationLink(value: Route.rock(other.id)) {
                            Chip(emoji: other.family.emoji, text: other.name, color: Theme.color(for: other.family).opacity(0.2))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var funFactsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(emoji: "🤩", text: "Fun facts")
            ForEach(rock.funFacts, id: \.self) { fact in
                HStack(alignment: .top, spacing: 12) {
                    Text("💡")
                    Text(fact)
                        .font(Theme.rounded(18, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .card()
    }
}

/// Mohs scale from 1 to 10 with everyday reference objects.
struct HardnessScaleView: View {
    let range: HardnessRange
    let color: Color

    private let markers: [(value: Double, emoji: String, label: String)] = [
        (2.5, "💅", "Fingernail"),
        (3.5, "🪙", "Coin"),
        (5.5, "🔩", "Steel nail"),
        (7, "🔮", "Quartz"),
        (10, "💎", "Diamond")
    ]

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let position = { (value: Double) in CGFloat((value - 1) / 9) * width }
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.softCard, Theme.subtleInk.opacity(0.35)], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 18)
                    Capsule()
                        .fill(color)
                        .frame(width: max(18, position(range.max) - position(range.min) + 18), height: 18)
                        .offset(x: max(0, position(range.min) - 9))
                    ForEach(markers, id: \.value) { marker in
                        Rectangle()
                            .fill(Theme.ink.opacity(0.4))
                            .frame(width: 2, height: 26)
                            .offset(x: position(marker.value) - 1)
                    }
                }
                .frame(height: 26)
            }
            .frame(height: 26)

            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    ForEach(markers, id: \.value) { marker in
                        VStack(spacing: 0) {
                            Text(marker.emoji).font(.system(size: 20))
                            Text(marker.label)
                                .font(Theme.rounded(11, weight: .semibold))
                                .foregroundStyle(Theme.subtleInk)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(width: 56)
                        .offset(x: CGFloat((marker.value - 1) / 9) * geometry.size.width - 28)
                    }
                }
            }
            .frame(height: 56)
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hardness \(range.displayText) out of 10")
    }
}
