# Rock Detective — Design Plan

A native iPadOS app that helps kids (about 6–12 years old) identify the rocks
they find. Kids take or pick a photo, get an immediate best guess with
kid-friendly details, and can become a "rock detective" by answering a few
simple clue questions that make the answer more certain. Every find is saved
to their personal rock collection.

---

## 1. Research: where should the data come from?

### 1.1 Options considered

| Option | What it is | Pros | Cons |
|---|---|---|---|
| **A. Cloud vision / LLM API** (e.g. a multimodal LLM, Google Cloud Vision) | Upload the photo, get a label back | Broad coverage, no model to maintain | Needs network (kids are often outdoors with poor signal); 1–6 s latency; per-call cost; API key must live on a server we'd have to run; **sends a child's photo to a third party** (photos are personal information under COPPA and App Store guideline 5.1.4(b); guideline 1.3 says Kids Category apps "may not send personally identifiable information or device information to third parties"); generic vision APIs return labels like "rock"/"stone", not rock types; LLMs answer confidently even when wrong and there is no rigorous published benchmark of them for rock ID |
| **B. Specialist identification service** | iNaturalist, Mindat | Expert-curated | iNaturalist explicitly does **not** support rocks; Mindat's API is a text/data API (minerals, localities), not photo identification |
| **C. On-device classifier trained on local rock photos** (Create ML / Core ML) | Train a CNN on a labelled photo set | Fast (tens of ms), offline, private | Needs a large, **licensed**, well-labelled field-photo dataset per class. Published accuracies of 93–98 % are on small, curated label sets and lab-style photos; public datasets found have unclear licences (Kaggle mirrors) or attribution/share-alike terms; one photo can't show hardness, acid reaction or density, which is how geologists actually tell look-alikes apart |
| **D. On-device "rock key": curated knowledge base + photo clues + field-test questions** | Encode each rock's diagnostic properties; read visual clues from the photo; ask kid-safe tests (vinegar fizz, nail scratch, float test) | Scientifically grounded (mirrors how geologists identify hand samples); fully offline and private; instant; explainable to kids ("I see layers!"); no dataset licensing | Photo-only accuracy is modest; relies on kids answering a few questions for high confidence |

### 1.2 Decision

**Local data source, hybrid design (D + an embedding hook for C).**

1. **Primary data source: a curated, bundled rock knowledge base**
   (`rocks.json`, 24 common rock types across all three families) with:
   kid-friendly descriptions, formation, minerals, Mohs hardness, where found,
   fun facts, rock-cycle links, and a *likelihood table* for 19 observable
   clues (e.g. P(fizzes with vinegar | limestone) ≈ 0.9).
2. **Photo analysis on device**: extract scientifically meaningful visual cues
   from a centered square crop (side = 60 % of the photo's shorter edge),
   using Core Graphics + plain Swift math
   (portable and testable):
   * color tone (median brightness) → light felsic vs dark mafic rocks;
   * warm hue (fraction of clearly pink/red/orange pixels, saturation ≥ 0.27);
   * grain = local contrast (5×5 standard deviation), discounted by layer
     coherence, because layers make *lined-up* contrast and grains make
     contrast in every direction;
   * salt-and-pepper specks (pixels far from their 9×9 neighbourhood);
   * layers = block-normalised structure-tensor coherence (one strong edge
     can't fake it, stripes through the whole picture do);
   * glassy shine = bright colourless highlights, measured only on darker
     bodies (on light rocks white minerals look the same as glare), and
     ignored by the speck and layer measures.
3. **Kid field tests** chosen adaptively (most useful question first).
4. **Reference-picture matching hook**: a k-nearest-neighbour matcher over
   Apple Vision feature prints (`VNGenerateImageFeaturePrintRequest`) that is
   switched on automatically when a curated, licensed reference gallery is
   added to the bundle (`ReferenceSamples/<rockID>/*.jpg`). We ship without
   reference pictures because we could not verify licences for a public
   dataset; the engine and its tests are in place so the gallery can be added
   later without code changes.

Why: kids' privacy (no photo ever leaves the iPad, no account, no network),
offline use in the field, speed (everything runs in well under a second),
scientific honesty (the app shows how sure it is and *why*, and teaches the
real tests geologists use), and no recurring cost.

### 1.3 Matching algorithm (local data)

**For picture matching (when a reference gallery exists):** compute a Vision
feature print per image (an embedding from Apple's on-device network), then
**distance-weighted k-NN** (k = 5) against the gallery. Feature-print distances
are relative (not normalised), so votes use `w = 1 / (d + ε)` and are turned
into per-rock likelihoods with Laplace smoothing. This beats colour histograms
or SIFT-style keypoints for textured natural surfaces and needs no training;
once the gallery reaches ~50+ images per rock, a Create ML transfer-learned
classifier (same feature extractor + logistic regression) is the upgrade path.

**For the knowledge base (always on):** a **naive Bayes classifier with
virtual (soft) evidence**:

```
log score(rock) = log prior(rock)
               + Σ answered clues     log P_ε(answer | rock)
               + w_photo · Σ photo cues  log Σ_v P(v | rock) · q(v)
               + w_ref   · log P(reference votes | rock)        (if gallery)
posterior = softmax(log scores)
```

* `prior` ∝ how common the rock is at the Earth's surface / where kids look
  (1–5 scale), so an uninformative photo favours sandstone over obsidian.
* `P_ε` adds a "kid mistake" rate: each likelihood is mixed 8 % with a
  uniform guess (for yes/no, `P_ε = ε + (1 − 2ε)·P` with ε = 4 %), so one
  wrong answer can't eliminate the right rock and log(0) never happens. The
  rate was chosen with a simulation sweep (0 – 12 %): accuracy is flat, and 8 %
  gives the best 5-question adaptive accuracy.
* "Not sure" answers are simply skipped (no information).
* Photo cues are *soft*: each cue gives a belief `q` (clamped to 0.2–0.8) that
  the clue is true; Pearl's virtual-evidence rule `Σ_v P(v|rock)·q(v)` folds it
  in, down-weighted by `w_photo = 0.7` because photos are fooled by lighting.
* A kid's own answer to a clue replaces the photo's guess for that clue.
* Sums run in catalog order, so results are bit-for-bit reproducible.

**Adaptive questions:** choose the unanswered, applicable question with the
largest **expected information gain** (reduction in Shannon entropy of the
posterior), like a good game of 20 Questions. Stop suggesting questions when
the best match passes 90 % or no question gains ≥ 0.02 bits. Some questions
have prerequisites (e.g. "Are the pebbles round?" only after "made of
pebbles = yes"); an unlocked follow-up gets a ×2 utility bonus so the
conversation stays on topic. Tests that need a tool or a grown-up (vinegar,
nail) are gently discounted: `utility = gain / (1 + 0.15·(effort − 1))`.
When the photo already points to an answer, the clue card says so ("From your
photo I'd guess Yes. Look closely and check!"), which teaches kids to verify.

Complexity: 24 rocks × 19 clues — scoring is O(R·C) ≈ 450 operations,
planning is O(R·C·A) ≈ 1 500; both take microseconds. Photo analysis runs on a
downsampled 160×160 crop (~25 k pixels): tens of milliseconds.

### 1.4 Sources

* Apple App Review Guidelines 1.3 & 5.1.4 — <https://developer.apple.com/app-store/review/guidelines/>
* iNaturalist does not accept rocks — <https://help.inaturalist.org/en/support/solutions/articles/151000170238>
* Mindat API / OpenMindat (data API, not photo ID) — <https://search.r-project.org/CRAN/packages/OpenMindat/index.html>
* Deep CNN rock ID on field images (6 classes, 97.96 %) — <https://www.mdpi.com/2227-7390/7/8/755>
* Transfer learning for rock images (ResNet34) — <https://public-pages-files-2025.frontiersin.org/journals/earth-science/articles/10.3389/feart.2022.1079447/text>
* Vision feature prints & `computeDistance` — <https://developer.apple.com/forums/thread/721760>, <https://fritz.ai/compute-image-similarity-using-computer-vision-in-ios/>
* Create ML feature extractor (transfer learning) — <https://developer.apple.com/documentation/createml/mlimageclassifier/featureextractortype>
* Vinegar (acid) test for calcite / limestone — <https://www.coolscience.org/uploads/1/0/7/7/107782681/test_for_limestone.pdf>, <https://kids.nationalgeographic.com/science/article/rock-on>
* Consumer rock-ID app accuracy is self-reported and unverified — <https://www.rockhounding.org/blog/best-rock-identification-apps/>
* Rock datasets with unclear/attribution licences — <https://gts.ai/dataset-download/rock-classification-dataset/>, <https://universe.roboflow.com/rockws/rock_images_2>

---

## 2. Scientific scope

24 rocks, chosen because kids commonly find or see them:

| Igneous (cooled from melted rock) | Sedimentary (pieces/shells/plants pressed together) | Metamorphic (changed by heat and pressure) |
|---|---|---|
| Granite, Diorite, Gabbro (intrusive, coarse) | Sandstone, Shale, Conglomerate, Breccia (clastic) | Slate, Phyllite, Schist, Gneiss (foliated) |
| Basalt, Andesite, Rhyolite (extrusive, fine) | Limestone, Chalk (carbonate) | Marble, Quartzite (non-foliated) |
| Obsidian, Pumice, Scoria, Tuff (glassy / vesicular / ash) | Coal (organic), Chert/Flint (silica) | |

Each rock record contains: id, name, how to say it, category, sub-type,
kid summary, how it formed, minerals, Mohs hardness range, where to find it,
2–3 fun facts, rock-cycle links (`formsFrom`, `canBecome`), commonness,
illustration style, and clue likelihoods.

Accuracy rules for content:
* Hardness values are for the rock's main minerals (e.g. limestone ≈ 3,
  quartzite ≈ 7). Steel nail ≈ 5.5.
* Only carbonate rocks (limestone, chalk, marble; weakly some sandstones,
  conglomerates, breccias, shales with calcite cement) fizz with acid.
* Igneous rocks do not contain fossils (likelihood ≤ 0.03).
* Only highly vesicular pumice floats (it can sink once waterlogged).
* Safety notes: grown-up help for nail scratch & vinegar tests; obsidian
  edges are sharp; never taste rocks.
* The app shows confidence honestly ("Pretty sure", "Good guess",
  "Just a hunch") and always lists look-alikes.

### 2.1 Clue questions (19)

| id | Kid question | From photo? |
|---|---|---|
| color | What color is most of your rock? (Light / In-between / Dark) | ✔ |
| reddish | Is it pink, red or orange-ish? | ✔ |
| grains | Can you see lots of little grains or crystals, like sugar? | ✔ |
| speckled | Does it have different-colored specks, like salt and pepper? | ✔ |
| quartzBits | Can you see clear or smoky-gray glassy bits, like tiny pieces of ice? | |
| sparkle | Does it sparkle or glitter when you tilt it in the light? | |
| glassy | Is it smooth and shiny, like glass? | ✔ |
| layers | Does it have layers, stripes or bands? | ✔ |
| sheets | Does it split or flake into flat sheets? | |
| holes | Does it have lots of little holes, like a sponge? | |
| floats | Does it float in water? | |
| fizz | Does it fizz when you drip vinegar on it? | |
| pebbles | Is it made of pebbles or rock pieces stuck together? | |
| roundPebbles | Are those pebbles round and smooth? (only if pebbles = yes) | |
| gritty | Does it feel rough like sandpaper? | |
| nailScratch | Can a steel nail scratch it? | |
| marks | Does it leave a mark on paper or fingers, like chalk? | |
| fossils | Can you see fossils, like shells or leaf prints? | |
| lightweight | Does it feel surprisingly light for its size? | |

---

## 3. Architecture

```
RockID.xcodeproj
├── RockID/                 SwiftUI app (iPad only, iPadOS 17+)
│   ├── App/                App entry, AppModel (dependency container)
│   ├── Views/              Home, Identify, Result, Clue card, Rock Book,
│   │                       Rock detail, Collection, Rock cycle, Mascot
│   └── Support/            Camera picker, theme, haptics
├── RockIDUITests/          XCUITest end-to-end tests
└── Packages/RockKit/       Swift package with all logic (tested on macOS
    │                       with `swift test` and on the iPad simulator)
    ├── Catalog/            Rock, ClueQuestion, RockCatalog (+ rocks.json)
    ├── Engine/             RockMatcher (Bayes), QuestionPlanner (info gain),
    │                       ReferenceMatcher (k-NN), RockIdentifier (facade)
    ├── Imaging/            ImageLoader (ImageIO), PixelBuffer, PhotoAnalyzer,
    │                       PhotoEvidence, FeaturePrinter (Vision),
    │                       CropFraming (crop math), SubjectFinder (Vision saliency)
    ├── Art/                RockArtRenderer (procedural CoreGraphics art)
    ├── History/            Finding, HistoryStore (JSON + JPEG files)
    └── Session/            IdentificationSession (@Observable view model)
```

* **No network, no accounts, no third-party SDKs.** Camera permission only.
* Swift 6 language mode, strict concurrency. Logic types are `Sendable`
  value types; UI-facing state is `@MainActor @Observable`.
* Photo analysis runs off the main actor; the UI shows a short "looking for
  clues" animation while it runs.
* Illustrations of each rock are drawn procedurally (deterministic seeded
  RNG) to show the real diagnostic textures (speckles, layers, holes,
  bands, pebbles) — no image licensing needed.

### 3.1 Persistence

`HistoryStore` keeps `history.json` (array of `Finding`) and `photos/<id>.jpg`
(downscaled to ≤ 1024 px, JPEG q 0.8) in Application Support. Writes are
atomic. A corrupt history file is moved aside (`history.corrupt-<date>.json`)
and the app starts with an empty list instead of crashing.

`Finding` = id, date, photo file, best rock id, confidence, top-5 ranking,
answers, photo evidence, optional nickname. Re-opening a finding restores the
session so kids can keep answering clues later; the entry is updated in place.

### 3.2 User flow (3 taps to an answer)

1. **Home**: big "Take a Photo" and "Choose a Photo" buttons, "My Rocks"
   and "Rock Book" cards, discovery progress ("You found 3 of 24 rocks!").
2. **Frame your rock**: the photo sits under a square frame with a dashed
   aiming circle. Kids pinch (zooming around their fingers) and drag so
   only the rock fills it; "Zoom out" resets and "Cancel" goes back without
   saving anything. VoiceOver can zoom (adjustable) and move the photo
   (named actions). When Vision
   objectness saliency finds the main object, the frame glides onto it
   (unless the kid has already moved the photo) and a "Center rock" button
   can bring it back. Every photo source goes through this step: camera,
   library, and practice mode.
3. **Looking for clues** (≈ 0.1–0.5 s): mascot with magnifying glass.
4. **Result**: photo + "Clues I spotted", best match with art, family badge,
   confidence stars, "Could also be…", and a **Detective clue card**
   (Yes / No / Not sure, with how-to and safety tip). Each answer instantly
   re-ranks; answered clues can be changed. "Learn all about it" opens the
   rock page. The find is auto-saved to the collection.
5. **Rock page**: how to say it, family, how it formed, minerals, hardness
   scale with everyday objects, where to find it, fun facts, rock cycle links.
6. **My Rocks**: grid of saved finds; tap to reopen; delete with confirmation.
7. **Rock Book**: all 24 rocks by family; discovered ones get a star; a
   Rock Cycle explainer.

### 3.3 Kid-friendly design rules

* Rounded, large type; 64 pt+ primary buttons; bright family colors
  (igneous = lava orange, sedimentary = sandy teal, metamorphic = purple).
* Short sentences, no jargon without explanation ("foliated = squished into
  layers").
* Emoji and a friendly pebble mascot; light haptics and a sparkle burst on
  results; respects Reduce Motion.
* VoiceOver labels on controls; large fixed-size rounded type. (Dynamic
  Type scaling is future work.)
* No links out, no purchases, no ads → no parental gate needed.

---

## 4. Performance targets

| Step | Target |
|---|---|
| Load + downsample a 12 MP photo | < 300 ms |
| Photo analysis (160 px working size) | < 150 ms |
| Bayesian scoring, all clues answered | < 1 ms |
| Next-question planning | < 5 ms |
| Photo → first result on screen | < 1 s |

---

## 5. Predefined test cases

Unit tests live in `Packages/RockKit/Tests/RockKitTests` (Swift Testing);
UI tests in `RockIDUITests` (XCTest). Test names carry the IDs below.

### 5.1 Knowledge base (KB)

| ID | Test | Expected |
|---|---|---|
| KB-01 | Load bundled catalog | 24 rocks, 19 questions, no throw |
| KB-02 | Unique, non-empty ids & names | all unique |
| KB-03 | Every rock has a likelihood for every yes/no clue | 0 < p < 1 |
| KB-04 | Every color distribution sums to 1 (±0.01) | true |
| KB-05 | Each family has ≥ 6 rocks | igneous 10, sedimentary 8, metamorphic 6 |
| KB-06 | Hardness ranges valid | 1 ≤ min ≤ max ≤ 10 |
| KB-07 | Rock-cycle links reference existing rocks | all resolvable |
| KB-08 | Question prerequisites reference existing questions | true |
| KB-09 | Kid text present (summary, formation, ≥2 fun facts, minerals, where) | non-empty |
| KB-10 | Science: limestone, chalk, marble fizz ≥ 0.85; non-carbonates ≤ 0.2 | true |
| KB-11 | Science: quartzite & chert scratched by nail ≤ 0.1; limestone, chalk, coal ≥ 0.8 | true |
| KB-12 | Science: only pumice floats ≥ 0.5 | true |
| KB-13 | Science: igneous fossils ≤ 0.03 | true |
| KB-14 | Science: Mohs — quartzite max ≥ 7, limestone ≤ 4, chalk ≤ 3 | true |
| KB-15 | Science: families — granite igneous, sandstone sedimentary, marble metamorphic … | correct |
| KB-16 | Malformed catalog JSON | throws `CatalogError` |

### 5.2 Matcher (MT)

| ID | Evidence | Expected |
|---|---|---|
| MT-01 | No evidence | probabilities sum to 1; ranking follows commonness priors |
| MT-02 | fizz=yes, fossils=yes, layers=yes | limestone #1 |
| MT-03 | glassy=yes, color=dark, holes=no | obsidian #1 |
| MT-04 | floats=yes, holes=yes, lightweight=yes | pumice #1, ≥ 0.8 |
| MT-05 | holes=yes, color=dark, floats=no, reddish=yes | scoria #1 |
| MT-06 | pebbles=yes, roundPebbles=yes | conglomerate #1 |
| MT-07 | pebbles=yes, roundPebbles=no | breccia #1 |
| MT-08 | layers=yes, grains=yes, speckled=yes, sheets=no | gneiss #1 |
| MT-09 | sparkle=yes, layers=yes, sheets=yes, grains=yes | schist #1 |
| MT-10 | sheets=yes, color=dark, nailScratch=no, sparkle=no | slate #1 |
| MT-11 | color=light, grains=yes, speckled=yes, sparkle=yes, fizz=no | granite #1 |
| MT-12 | color=dark, grains=yes, speckled=yes | gabbro #1 |
| MT-13 | fizz=yes, grains=yes, sparkle=yes, fossils=no | marble #1 |
| MT-14 | gritty=yes, layers=yes, grains=yes, fizz=no | sandstone #1 |
| MT-15 | marks=yes, color=dark, lightweight=yes | coal #1 |
| MT-16 | marks=yes, color=light, fizz=yes | chalk #1 |
| MT-17 | "Not sure" answers | posterior identical to no answer |
| MT-18 | Contradictory answers (floats=yes, fizz=yes, glassy=yes, pebbles=yes) | valid distribution, no NaN, top < 0.9 |
| MT-19 | One wrong answer (granite clues + fizz=yes) | granite still in top 3 |
| MT-20 | Self-consistency: each rock's most-likely answer to every clue | that rock is #1 (all 24) |
| MT-21 | Monte-Carlo: 200 simulated kids per rock answering all clues (seeded) | within 3 (top-1) / 2 (top-3) points of the Bayes-optimal classifier for the simulation (exact probabilities, uniform prior, no mistake allowance); top-1 ≥ 65 %, top-3 ≥ 90 % (see §7) |
| MT-22 | Soft photo evidence only (dark, fine, glassy) | obsidian in top 3, but confidence < answers-based |
| MT-22b | Kid answers a clue the photo also guessed | photo guess for that clue is ignored |
| MT-23 | Photo evidence weight 0 | same as no evidence |
| MT-24 | Confidence level mapping | ≥0.6 sure, ≥0.35 good guess, else hunch |
| MT-25 | Uniform-prior option | every rock equally likely with no evidence |

### 5.3 Question planner (QP)

| ID | Test | Expected |
|---|---|---|
| QP-01 | No evidence | returns a question with gain > 0, never `roundPebbles` |
| QP-02 | After pebbles=yes | next question is `roundPebbles` |
| QP-03 | Never repeats an answered (or "not sure") question | true |
| QP-04 | Posterior top ≥ 0.9 | returns nil |
| QP-05 | All questions answered | returns nil |
| QP-06 | Adaptive simulation (≤ 5 questions, seeded kids) | top-3 ≥ 70 %, top-1 ≥ 42 % and ≥ 1.5× five random questions (see §7) |
| QP-07 | Gains are non-negative; suggestions sorted by utility | true |

### 5.4 Photo analysis (IA)

Synthetic images are generated in the tests with Core Graphics.

| ID | Image | Expected |
|---|---|---|
| IA-01 | Uniform dark gray | color: dark most likely; grains & layers low |
| IA-02 | Uniform near-white | color: light most likely |
| IA-03 | Horizontal stripes | layers high (≥ 0.7 belief) |
| IA-04 | Diagonal stripes | layers high (orientation-invariant) |
| IA-05 | Random salt-and-pepper speckles | speckled & grains high, layers low |
| IA-06 | Black with small white highlights | glassy high |
| IA-07 | Orange-red | reddish high; gray image reddish low |
| IA-08 | 1×1 and 3×3 images | no crash, neutral evidence |
| IA-09 | Yes/no beliefs always within [0.2, 0.8]; color beliefs sum to 1 | true |
| IA-10 | Procedural art of granite / basalt / gneiss / obsidian | that rock in photo-only top 5 |
| IA-11 | ImageLoader downsamples a 4000×3000 JPEG to ≤ max side and keeps aspect | true |
| IA-12 | ImageLoader applies EXIF orientation (rotated 90°) | width/height swapped |
| IA-13 | Invalid image data | throws |
| IA-14 | Practice photos (art on a table) of all 24 rocks, photo only | right rock in top 5 for ≥ 18, top 3 for ≥ 12; granite #1 with "specks" clue |
| IA-15 | Stripes vs grains; white specks vs glare | stripes not grainy; white specks not glassy |
| IA-16 | Photo suggestions | only for clear evidence (yes ≥ 0.65, no ≤ 0.3, tone ≥ 0.5) |

### 5.5 Reference matcher (RM)

| ID | Test | Expected |
|---|---|---|
| RM-01 | Empty gallery | no evidence (nil) |
| RM-02 | Query equal to a granite vector | granite highest likelihood |
| RM-03 | k larger than gallery | uses all, no crash |
| RM-04 | Likelihoods smoothed | every rock > 0 |
| RM-05 | Vision feature prints: striped query closer to striped refs than speckled refs | true (skipped if Vision unavailable) |

### 5.6 History (HS)

| ID | Test | Expected |
|---|---|---|
| HS-01 | Add finding + photo, reload new store at same folder | identical finding, photo file exists |
| HS-02 | Findings sorted newest first | true |
| HS-03 | Update finding (new answers) persists | true |
| HS-04 | Delete removes entry and photo file | true |
| HS-05 | Corrupt history.json | store loads empty, corrupt file kept aside |
| HS-06 | Photo saved ≤ 1024 px | true |
| HS-07 | `discoveredRockIDs` = unique best matches | true |
| HS-08 | Delete all | empty list, photos folder empty |

### 5.7 Session (SS)

| ID | Test | Expected |
|---|---|---|
| SS-01 | Start with image → result and next question available | true |
| SS-02 | Answer clue → result updates, finding saved/updated in store | true |
| SS-03 | Change an answer back to "not sure" | ranking returns to before |
| SS-04 | Restore session from saved finding | same ranking, same answers |

### 5.8 Performance (PF)

| ID | Test | Target |
|---|---|---|
| PF-01 | Score all 24 rocks with all clues answered (avg of 1 000) | < 1 ms |
| PF-02 | Plan next question (avg of 100) | < 5 ms |
| PF-03 | Analyze 160 px photo | < 150 ms |
| PF-04 | Load + downsample 4000×3000 JPEG | < 300 ms |

### 5.9 UI (UI) — XCUITest on iPad simulator

| ID | Flow | Expected |
|---|---|---|
| UI-01 | Launch | Title, "Choose a Photo", "My Rocks", "Rock Book" visible |
| UI-02 | Practice rock (UI-test hook) → result | best-match name & "Could also be" visible |
| UI-03 | Answer a clue | clue moves to "Your clues"; result still shown |
| UI-04 | Back to home → My Rocks | the find is listed |
| UI-05 | Relaunch app (no reset) | find still in My Rocks (persistence) |
| UI-06 | Rock Book → Granite | shows "Igneous" and hardness section |
| UI-07 | Delete find in My Rocks | list empty state shown |
| UI-08 | Practice rock → crop screen: cancel; then zoom out, pinch, use | cancel saves nothing; zoom out returns to 100 %; pinch zooms; the identified photo is the smaller cropped square |

### 5.10 Photo cropping (CR) — added with the "Frame your rock" feature

| ID | Test | Expected |
|---|---|---|
| CR-01 | Full framing of landscape, portrait and square photos | centered square of the shorter side |
| CR-02 | Panning far in every direction | crop stops at the photo's edges; no vertical room at zoom 1 on landscape |
| CR-03 | Zoom limits | 1 … min(8, shorter side / 160 px); tiny photos can't zoom |
| CR-04 | Zooming after a pan | the spot in the middle of the frame stays put (±1 px) |
| CR-10 | Pinch zoom around an off-center anchor | the photo spot under the fingers stays put (±2 px); bad anchors fall back to the center |
| CR-05 | Framing a given square | round-trips within 1 px; too-small squares are limited by max zoom around the same center |
| CR-06 | Suggested square around an object | padded, square, shifted (not shrunk) to stay inside the photo |
| CR-07 | 2,000 random framings incl. NaN and out-of-range values | always a whole-pixel square inside the photo, never smaller than the zoom limit allows |
| CR-08 | Vision subject finder on an off-center rock | suggestion contains and is centered on the rock (skipped where Vision saliency is unavailable) |
| CR-09 | Off-center rock photo, uncropped vs cropped (granite, basalt, gneiss) | cropped rank ≤ 3 and better than uncropped (measured: 9–22 → 1) |

---

## 6. Out of scope / future work

* Curated, licence-checked reference photo gallery (USGS public-domain
  images are a good start) to switch on k-NN picture matching, then a
  Create ML classifier once there are enough photos per rock.
* Minerals and gemstones (quartz crystals, pyrite …) as a second catalog.
* Calibrating photo-cue thresholds against a labelled field photo set.
* Localization.

---

## 7. Results

All numbers below come from the test suite (`scripts/test-all.sh`).

| Suite | macOS (`swift test`) | iPad simulator (iOS 27) |
|---|---|---|
| RockKit unit tests | 94 / 94 pass | 94 / 94 pass (RM-05 and CR-08 skipped: the simulator has no Vision feature-print or saliency model; both pass on macOS) |
| UI tests (UI-01 … UI-08 + learn-more flow) | — | 5 / 5 pass |

**Accuracy (simulated kids, seeded).** Each simulated kid draws every clue
answer from its rock's catalog probabilities and never makes mistakes, and
every rock is equally likely. These numbers measure how well the clues
separate the rocks under the model's own assumptions, not real-world accuracy.

| Scenario | Top-1 | Top-3 |
|---|---|---|
| Bayes-optimal for this simulation (exact probabilities, uniform prior), all clues | 69.0 % | 91.8 % |
| Rock Detective matcher, all clues | 67.3 % | 91.1 % |
| 5 adaptive questions | 46.5 % | 73.1 % |
| 5 random questions | 23.0 % | 49.2 % |
| Photo only, practice photos of all 24 rocks | 6 / 24 | 15 / 24 (top-5: 21 / 24) |

**Speed (debug build, simulator):** scoring 0.5 ms, next question 1.5 ms,
photo analysis 47 ms, 12 MP decode + downsample 70 ms.

### What changed after measuring (and why)

* **MT-21 / QP-06 thresholds.** The first targets (75 % / 92 %, 60 % adaptive)
  were set before measuring. Simulated kids sample each clue from a rock's
  catalog probabilities, and on that data even the Bayes-optimal classifier
  tops out at ≈ 69 % top-1 / 92 % top-3, because the remaining confusions are
  the genuinely hard ones (diorite ↔ granite ↔ gabbro, basalt ↔ andesite,
  shale ↔ slate, chert ↔ obsidian, limestone ↔ marble). The tests now check
  that the matcher stays within 3 / 2 points of that classifier, plus absolute
  floors. The gap comes from the matcher's deliberate commonness prior and
  mistake allowance. This is why the app always shows "Could also be…" and an
  honest confidence.
* **Reference classifier corrected.** An independent fact-check of the README
  noticed the first "ceiling" (68.2 % / 91.6 %) still used the commonness
  prior, which isn't optimal when every rock is equally likely. The matcher
  gained a `useCommonnessPrior` setting, and MT-21 now compares against the
  true Bayes-optimal classifier (uniform prior).
* **Added the quartz clue.** The confusion analysis showed diorite misread as
  granite most often. Field guides separate them by quartz, so the 19th clue
  ("glassy bits, like ice") was added: correct diorite IDs rose from 52 to 100
  out of 200, and granite and quartzite also improved.
* **Mistake rate 12 % → 8 %** (sweep above) and the follow-up bonus (so
  "Are the pebbles round?" comes right after "made of pebbles? yes").
* **Photo analysis.** A screenshot review showed a granite practice photo read
  as "smooth" and the tan table counted as "reddish". The grain measure became
  local contrast with a layer discount, the crop tightened to 60 %, warm hue
  needs saturation ≥ 0.27, and glare is excluded from specks and layers.
  Real-world calibration still needs a labelled photo set (see §6).

* **"Frame your rock" review.** An adversarial review of the crop feature
  (four lenses, each finding challenged by a skeptic) confirmed eight issues,
  all fixed: gesture jumps after a system-cancelled pinch or drag, the
  misleading "Whole photo" label (now "Zoom out"), a late auto-center
  overriding the kid's choice, pinch not zooming around the fingers, no way
  to pan with VoiceOver or Switch Control, fixed-height layout breaking in
  Slide Over, two presentation races on the photo-library path, and a UI test
  that couldn't tell whether the crop was really applied.

## 8. Building and testing

```
open RockID.xcodeproj                      # run the RockID scheme on an iPad
scripts/test-all.sh                        # every test, macOS + iPad simulator
swift test --package-path Packages/RockKit # fast logic tests only
```

UI tests launch the app with `-uiTesting -practiceRock <rockID>`. That uses a
separate history folder and shows a "Practice Rock" button that feeds a
procedurally drawn photo through the real identification flow, because the
simulator has no camera. `-resetHistory` clears that folder.

