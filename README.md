# Rock Detective

A kid-friendly iPad app that identifies rocks. Take or choose a photo, get an
instant best guess with kid-sized facts, then play rock detective: answer a few
simple clue questions (Does it fizz in vinegar? Does it have layers?) to become
more certain. Every find is saved to **My Rocks**, and the **Rock Book** teaches
all 24 rocks and the rock cycle.

* **Private and offline.** Everything runs on the iPad. No network, accounts,
  ads, or analytics. Photos never leave the device.
* **Scientifically grounded.** A curated knowledge base of 24 common rocks,
  identified the way geologists do it: visual clues plus simple field tests,
  combined with Bayesian reasoning that always shows how sure it is.
* **Fast.** Photo to answer in well under a second.

See [docs/DESIGN.md](docs/DESIGN.md) for the research, design, test plan, and
measured results.

## Project layout

| Path | What's there |
|---|---|
| `RockID/` | SwiftUI iPad app (iPadOS 17+) |
| `RockIDUITests/` | XCUITest end-to-end tests |
| `Packages/RockKit/` | All logic: rock catalog (`Resources/rocks.json`), Bayesian matcher, question planner, photo analysis, rock art, history, session |
| `scripts/test-all.sh` | Runs every test on macOS and the iPad simulator |

## Build and test

```bash
open RockID.xcodeproj
```

```bash
scripts/test-all.sh
```
