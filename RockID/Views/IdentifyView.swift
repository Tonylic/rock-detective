import RockKit
import SwiftUI

/// Photo → result → detective clues.
struct IdentifyView: View {
    let session: IdentificationSession
    @State private var celebrations = 0

    /// Two columns only when there is room (iPad landscape); otherwise one.
    private static let twoColumnWidth: CGFloat = 1000

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            switch session.phase {
            case .idle, .analyzing:
                AnalyzingView(photo: session.photo)
                    .transition(.opacity)
            case .ready:
                results
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
            CelebrationView(trigger: celebrations)
        }
        .animation(.easeInOut(duration: 0.35), value: session.phase)
        .navigationTitle("Rock Detective")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: session.phase == .ready)
        .sensoryFeedback(.selection, trigger: session.evidence.answers.count)
        .onChange(of: session.phase) { _, phase in
            if phase == .ready { celebrations += 1 }
        }
    }

    private var results: some View {
        GeometryReader { geometry in
            ScrollView {
                Group {
                    if geometry.size.width >= Self.twoColumnWidth {
                        HStack(alignment: .top, spacing: 24) {
                            VStack(spacing: 20) {
                                PhotoCard(photo: session.photo)
                                photoDetails
                            }
                            .frame(width: 360)
                            rightColumn
                        }
                    } else {
                        VStack(spacing: 20) {
                            HStack(alignment: .top, spacing: 20) {
                                PhotoCard(photo: session.photo, height: 260)
                                    .frame(width: 260)
                                PhotoCluesCard(clues: session.photoClues)
                            }
                            rightColumn
                            if !session.answeredClues.isEmpty {
                                AnsweredCluesCard(session: session)
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 1200)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var photoDetails: some View {
        VStack(spacing: 20) {
            PhotoCluesCard(clues: session.photoClues)
            if !session.answeredClues.isEmpty {
                AnsweredCluesCard(session: session)
            }
        }
    }

    @ViewBuilder
    private var rightColumn: some View {
        VStack(spacing: 20) {
            if let rock = session.bestRock {
                BestMatchCard(rock: rock, result: session.result)
            }
            if let question = session.nextQuestion {
                ClueQuestionCard(question: question, photoHint: session.evidence.photo?.suggestedAnswer(for: question.id)) { answer in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        session.answer(answer, to: question.id)
                    }
                }
                .id(question.id)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            } else {
                CaseClosedCard(level: session.result.level)
            }
            AlternativesCard(candidates: session.alternatives, catalog: session.catalog)
        }
    }
}

// MARK: - Analyzing

struct AnalyzingView: View {
    let photo: CGImage?

    var body: some View {
        VStack(spacing: 28) {
            if let photo {
                Image(decorative: photo, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 280, height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .shadow(radius: 10)
            }
            MascotView(size: 120, isSearching: true)
            Text("Looking for clues…")
                .font(Theme.rounded(34, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text("Checking colors, grains, specks, and layers")
                .font(Theme.rounded(20, weight: .medium))
                .foregroundStyle(Theme.subtleInk)
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("analyzingView")
    }
}

// MARK: - Photo

struct PhotoCard: View {
    let photo: CGImage?
    var height: CGFloat = 300

    var body: some View {
        Group {
            if let photo {
                Image(decorative: photo, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Theme.softCard
                    Text("🪨").font(.system(size: 80))
                }
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        .accessibilityLabel("Your rock photo")
    }
}

struct PhotoCluesCard: View {
    let clues: [PhotoClue]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(emoji: "🔎", text: "Clues I spotted")
            if clues.isEmpty {
                Text("This photo was tricky! Answer the detective questions to help me.")
                    .font(Theme.rounded(17, weight: .medium))
                    .foregroundStyle(Theme.subtleInk)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(clues) { clue in
                        Chip(emoji: clue.emoji, text: clue.text)
                    }
                }
                Text("Photos can be fooled by light, so your answers count more!")
                    .font(Theme.rounded(14, weight: .medium))
                    .foregroundStyle(Theme.subtleInk)
            }
        }
        .card(padding: 20)
        .accessibilityIdentifier("photoClues")
    }
}

// MARK: - Best match

struct BestMatchCard: View {
    let rock: Rock
    let result: MatchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 20) {
                RockArtView(rock: rock, size: 150)
                VStack(alignment: .leading, spacing: 8) {
                    Text("It looks like…")
                        .font(Theme.rounded(20, weight: .semibold))
                        .foregroundStyle(Theme.subtleInk)
                    Text(rock.name)
                        .font(Theme.rounded(48, weight: .black))
                        .foregroundStyle(Theme.ink)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .accessibilityIdentifier("bestMatchName")
                    Text("Say it: \(rock.sayIt)")
                        .font(Theme.rounded(17, weight: .medium))
                        .foregroundStyle(Theme.subtleInk)
                    FamilyBadge(family: rock.family)
                }
            }

            HStack(spacing: 12) {
                StarsView(count: result.level.stars)
                Text(result.level.title)
                    .font(Theme.rounded(24, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .fixedSize()
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 14) {
                ProgressView(value: result.confidence)
                    .tint(Theme.sunshine)
                    .scaleEffect(x: 1, y: 2, anchor: .center)
                Text("\(Int((result.confidence * 100).rounded()))% sure")
                    .font(Theme.rounded(18, weight: .bold))
                    .foregroundStyle(Theme.subtleInk)
                    .fixedSize()
                    .accessibilityIdentifier("confidenceText")
            }

            Text(rock.summary)
                .font(Theme.rounded(20, weight: .medium))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(result.level.encouragement)
                .font(Theme.rounded(17, weight: .semibold))
                .foregroundStyle(Theme.color(for: rock.family))
                .fixedSize(horizontal: false, vertical: true)

            NavigationLink(value: Route.rock(rock.id)) {
                Label("Learn all about \(rock.name)", systemImage: "book.fill")
                    .font(Theme.rounded(20, weight: .bold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
            }
            .buttonStyle(ChunkyButtonStyle(color: Theme.color(for: rock.family)))
            .accessibilityIdentifier("learnMoreButton")
        }
        .card()
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: rock.id)
    }
}

// MARK: - Detective clue

struct ClueQuestionCard: View {
    let question: ClueQuestion
    var photoHint: Answer?
    let onAnswer: (Answer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("🕵️ Detective clue")
                .font(Theme.rounded(18, weight: .heavy))
                .foregroundStyle(Theme.grape)
            HStack(alignment: .top, spacing: 16) {
                Text(question.emoji).font(.system(size: 56))
                Text(question.prompt)
                    .font(Theme.rounded(28, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("cluePrompt")
            }
            Text(question.howTo)
                .font(Theme.rounded(18, weight: .medium))
                .foregroundStyle(Theme.subtleInk)
                .fixedSize(horizontal: false, vertical: true)
            if let photoHint {
                Label("From your photo I'd guess \"\(question.label(for: photoHint))\". Look closely and check!", systemImage: "camera.viewfinder")
                    .font(Theme.rounded(17, weight: .semibold))
                    .foregroundStyle(Theme.sky)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("photoHint")
            }
            if let safety = question.safety {
                Label(safety, systemImage: "exclamationmark.shield.fill")
                    .font(Theme.rounded(17, weight: .semibold))
                    .foregroundStyle(Theme.lava)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.lava.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 14)], spacing: 14) {
                ForEach(question.displayOptions, id: \.answer) { option in
                    Button {
                        onAnswer(option.answer)
                    } label: {
                        VStack(spacing: 4) {
                            Text(option.emoji).font(.system(size: 34))
                            Text(option.label)
                                .font(Theme.rounded(20, weight: .heavy))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            if let detail = option.detail {
                                Text(detail)
                                    .font(Theme.rounded(13, weight: .medium))
                                    .multilineTextAlignment(.center)
                                    .opacity(0.9)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 96)
                        .padding(.horizontal, 6)
                    }
                    .buttonStyle(ChunkyButtonStyle(color: color(for: option.answer)))
                    .accessibilityIdentifier("answer_\(option.answer.rawValue)")
                }
            }
        }
        .card(fill: Theme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Theme.grape.opacity(0.5), lineWidth: 3)
        )
        .accessibilityIdentifier("clueCard")
    }

    private func color(for answer: Answer) -> Color {
        switch answer {
        case .yes: Theme.leaf
        case .no: Theme.lava
        case .notSure: Theme.subtleInk
        case .light: Theme.sky
        case .medium: Theme.ocean
        case .dark: Color(light: 0x4A4038, dark: 0x6B6157)
        }
    }
}

struct CaseClosedCard: View {
    let level: ConfidenceLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if level == .prettySure {
                CardTitle(emoji: "🎉", text: "Case closed!")
                Text("You're a real rock detective. Your find is saved in My Rocks.")
                    .font(Theme.rounded(19, weight: .medium))
                    .foregroundStyle(Theme.ink)
            } else {
                CardTitle(emoji: "🧭", text: "That's all my clues")
                Text("Some rocks are tricky even for geologists! Show it to a grown-up, a teacher, or a museum to be extra sure.")
                    .font(Theme.rounded(19, weight: .medium))
                    .foregroundStyle(Theme.ink)
            }
        }
        .card()
        .accessibilityIdentifier("caseClosedCard")
    }
}

// MARK: - Answers & alternatives

struct AnsweredCluesCard: View {
    let session: IdentificationSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(emoji: "📝", text: "Your clues")
            Text("Tap a clue to change it.")
                .font(Theme.rounded(14, weight: .medium))
                .foregroundStyle(Theme.subtleInk)
            FlowLayout(spacing: 8) {
                ForEach(session.answeredClues, id: \.question.id) { item in
                    Button {
                        withAnimation { session.clearAnswer(for: item.question.id) }
                    } label: {
                        HStack(spacing: 6) {
                            Text(item.question.emoji)
                            Text("\(item.question.shortLabel): \(item.question.label(for: item.answer))")
                                .font(Theme.rounded(16, weight: .semibold))
                            Image(systemName: "xmark.circle.fill").opacity(0.6)
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.softCard, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("answeredClue_\(item.question.id.rawValue)")
                }
            }
        }
        .card(padding: 20)
        .accessibilityIdentifier("yourClues")
    }
}

struct AlternativesCard: View {
    let candidates: [Candidate]
    let catalog: RockCatalog

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(emoji: "🤔", text: "Could also be…")
            HStack(spacing: 16) {
                ForEach(candidates) { candidate in
                    if let rock = catalog.rock(id: candidate.rockID) {
                        NavigationLink(value: Route.rock(rock.id)) {
                            HStack(spacing: 12) {
                                RockArtView(rock: rock, size: 70)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(rock.name)
                                        .font(Theme.rounded(20, weight: .heavy))
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                    Text("\(Int((candidate.probability * 100).rounded()))% chance")
                                        .font(Theme.rounded(15, weight: .medium))
                                        .foregroundStyle(Theme.subtleInk)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Theme.softCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("alternative_\(rock.id)")
                    }
                }
            }
        }
        .card(padding: 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("couldAlsoBe")
    }
}
