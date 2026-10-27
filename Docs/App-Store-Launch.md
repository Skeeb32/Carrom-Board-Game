# Carrom Duo — App Store launch draft

This document records what the current repository supports, a fact-based store listing draft, and the work still needed before a submission. It is not an App Store submission or a guarantee of approval.

## Project assessment

### Verified project state

| Area | What is in the repository now |
| --- | --- |
| App | Native SwiftUI app with a SpriteKit board; iOS 17 deployment target; iPhone and iPad device families. |
| Play | One-device pass-and-play and a computer opponent. The main match supports portrait and a side-panel landscape layout. |
| Shot model | Pull distance maps to launch speed. The custom 120 Hz solver uses SI motion units, swept-circle disc time-of-impact, sliding friction, impact impulses, rail rebounds, and pocket checks. Spin and tangential friction are not modeled. |
| Rules | Own-coin scoring, turn retention, striker foul handling, queen cover, and a board winner are present. This is a simplified point ruleset, not a verified tournament rules implementation. |
| Identity | Sign in with Apple is wired through AuthenticationServices. The returned first name is held in app state for the session; there is no Carrom Duo account backend or cloud profile. A demo player can enter without signing in. Email sign-in is explicitly marked unavailable in the preview. |
| Services and privacy | No third-party packages, analytics SDK, ad SDK, or game backend are configured. No support URL or privacy-policy URL is published/configured. Scores are in memory and do not persist. |
| Project quality | One app target and one XCTest target. Tests cover physics calculations, pockets, scoring/rules, rebounds, and computer shot planning. No UI tests, CI workflow, or release/archive automation is present. Automatic signing is selected, but no development team is set in the inspected build settings. |
| Branding | Walnut, cream, and gold visual direction; generated board art and a 1024 × 1024 app icon asset are present. The icon source is identified as concept artwork. |

### Strengths

- The core board game is playable without an account, which keeps the main interaction immediate.
- The board simulation and match rules are concentrated in `CarromScene.swift`, with scoring state communicated to SwiftUI through `MatchSnapshot`.
- The app has a distinct board-and-wood visual identity and a useful one-tap demo path.
- Existing tests exercise several prior gameplay regressions, including immediate scoring and the computer's video-like short shot.

### Main gaps and risks

1. **Rules and game completion need a deliberate ruleset review.** The implementation has custom point scoring and queen logic. Validate every foul, last-coin, queen, and win transition with a written rules table and human playthroughs.
2. **Authentication currently exceeds the product need.** There is no account-backed feature. Keep guest play; decide whether Apple sign-in meaningfully improves the product. If account creation is later implemented, add in-app deletion and a working service before release.
3. **No published support or privacy page exists.** These are submission blockers until valid public URLs exist and the privacy text matches the release binary.
4. **Accessibility and device coverage are unverified.** The UI uses many fixed-size fonts; the SpriteKit board is gesture-driven and has no meaningful VoiceOver shot controls. Evaluate larger text, VoiceOver, contrast, Reduce Motion, iPad layouts, and compact iPhones.
5. **Physics parameters are estimates.** Current masses, friction, and restitution are tuning constants, not measurements from a physical board. Compare recorded shots against real-board reference data before making realism claims.
6. **No release evidence yet.** The repository has no CI, TestFlight build, archive validation, store record, privacy disclosures, or captured store screenshots.

The public remote is `https://github.com/Skeeb32/Carrom-Board-Game.git`. The checked-out `main` branch was one commit ahead of `origin/main` during this review; the current work has not been pushed.

## Product identity

- **Recommended name:** Carrom Duo (10 characters). This matches the app display name and project identity.
- **Name status:** A broad App Store web search did not establish an exact listing, but this does not prove the name is available in App Store Connect. The exact name reservation and trademark clearance remain unverified. Check the intended storefronts and trademark databases before lock-in; Apple only confirms app-name availability during app record setup.
- **Subtitle draft:** `Pocket coins. Pass the phone.` (29 characters)
- **One-sentence value proposition:** A quick carrom match you can play together on one device—or against the computer.
- **Primary audience:** Carrom players and friends looking for a casual local match on an iPhone or iPad.
- **User problem:** Make it easy to start a shared-device carrom match without creating an account or finding an online opponent.
- **Differentiator:** Pass-and-play and computer play are both available in the current local prototype.
- **Brand voice:** Warm, playful, direct, and lightly competitive. Avoid claims of tournament accuracy or “realistic” physics until validated.
- **Alternative names:** No alternative is recommended pending name and trademark clearance. “Carrom” is descriptive of the game; “Duo” is common, so distinctiveness should be checked rather than assumed.

## App Store listing draft

All lengths below are within Apple's currently documented field limits. Recheck in App Store Connect at submission time.

| Field | Draft | Length / state |
| --- | --- | --- |
| Name | Carrom Duo | 10 / max 30; availability unverified |
| Subtitle | Pocket coins. Pass the phone. | 29 / max 30 |
| Promotional text | Pass the phone, line up a shot, and settle the next point at the carrom board. Play locally with a friend or take on the computer. | 130 / max 170 |
| Keywords | karrom,board,striker,coins,offline,local,computer,tabletop,queen,finger | 71 ASCII bytes / max 100 bytes |
| Primary category | Games | Confirm the exact App Store Connect choice |
| Secondary category | Board, if offered for the selected storefront/setup | Confirm in App Store Connect |
| Support URL | Not available yet — publish a page with real contact information | Blocked |
| Marketing URL | None currently | Optional; do not invent one |
| Privacy policy URL | Not available yet | Blocked |
| Copyright | Owner/year not confirmed | Confirm before submission |
| Age rating | Complete App Store Connect questionnaire from actual content | Not yet assessed |

### Description draft

> Set up the board, pull back the striker, and see where the shot takes you.
>
> Carrom Duo is a local carrom game for two people sharing one iPhone or iPad. Pass the device after a turn, or play a solo match against the computer.
>
> • Drag back from the striker to aim and choose your shot strength.  
> • Reposition the striker along the baseline before you shoot.  
> • Pocket your color to score and keep your turn.  
> • Watch the queen: cover it with one of your coins to claim its points.  
> • Play without creating an account.
>
> Carrom Duo is an early game build with a simplified scoring ruleset. Matches are local to the device. Online multiplayer, synced profiles, and account services are not included.
>
> Pull up a chair and take your shot.

This draft describes implemented UI and game logic only. Keep the prototype disclosure until rule behavior and the release experience have been validated. Remove or revise any sentence if the corresponding behavior changes.

## Screenshot storyboard

Capture real screens from the final release candidate, then add only typography and framing that do not imply unimplemented features. No screenshot assets have been captured for this draft.

| Order | Real screen / state to capture | Headline | Supporting copy | Composition / focal point |
| --- | --- | --- | --- | --- |
| 1 — Hook | Welcome screen | **Carrom, ready for a rematch.** | A quick local match, one device. | Full-bleed board art; keep the Carrom Duo identity and main call to action visible. Do not add fictitious social or online badges. |
| 2 — Core play | Fresh match board, two-player mode | **Pass the phone. Take your shot.** | Play together on one iPhone or iPad. | Square board centered with both score cards visible. |
| 3 — Controls | Board while the striker is being aimed | **Pull back. Pick your angle.** | Drag the striker to set your shot. | Board is the focal point; capture the actual aim line and a legal baseline placement. |
| 4 — Solo play | Computer mode before its move | **Practice against the computer.** | Choose a shot and see what comes back. | Show the actual computer mode selector, rack, and both player labels. Do not imply difficulty selection. |
| 5 — Match feedback | Actual score after a legal pocket | **Pocket your color. Keep the turn.** | The board tracks the match as you play. | Make the score and turn state readable; capture only after a real valid shot. |

For the primary 6.9-inch iPhone screenshot class, Apple's current accepted sizes include **1260 × 2736**, **1290 × 2796**, or **1320 × 2868 px** in portrait depending on device. Apple currently lists 13-inch iPad sizes **2064 × 2752** or **2048 × 2732 px** in portrait depending on device; iPad screenshots are required because the target includes iPad. Confirm the exact current device class and accepted size in App Store Connect when exporting. Screenshots must be genuine app captures, opaque, and free of unsupported claims.

## Icon and visual direction

The repository includes a 1024 × 1024 app icon in the Xcode asset catalog and a larger source concept at `Design/CarromBoardDuo-AppIcon-Concept.png`. The board, black and ivory coins, red queen, walnut, and gold palette align with the current app. Keep the icon simple at small sizes and review the final asset without an external device mockup. Confirm the current App Store icon and asset-catalog requirements before archive validation.

The existing SwiftUI views already use native controls, system fonts, SF Symbols, and the walnut/cream/gold theme. The next design pass should prioritize layout resilience, text scaling, and board accessibility over decorative effects.

## Privacy, security, and Apple review

### Observed from code

- There is no app-owned server, email authentication provider, analytics, ad network, or third-party package in the project.
- Demo play requires no personal information.
- The Apple sign-in entry point requests name and email scopes. The current callback reads the given name into view state; the project does not send it to a Carrom Duo server or persist a profile.
- There are no location, camera, microphone, contacts, or photo-library permission requests in the inspected source.
- The repository does not include a privacy manifest or privacy-policy document. Whether a privacy manifest is required must be checked against the final binary and Apple's current required-reason API list; absence of third-party SDKs alone is not a compliance determination.

### Confirmed blockers / potential review risks

- **Confirmed:** no public privacy-policy or support URL is configured. App Store Connect requires a privacy policy URL, and Apple's guidelines require an accessible in-app policy link. Publish accurate pages and add working links before submission.
- **Confirmed:** automatic code signing is selected, but no developer team is set in the inspected build settings. Select the correct team and validate a signed device archive before TestFlight.
- **Confirmed:** no account service exists. Keep the game playable without sign-in. If account creation is added, provide account deletion in-app and a real backend deletion path.
- **Potential:** Sign in with Apple may not add value for a local-only game. Test the value and ensure reviewers can reach the game without Apple credentials. Remove account UI if the product remains fully local.
- **Potential:** Apple Arcade wording can imply distribution or member-only functionality. The current UI now states that this build is not an Apple Arcade title and that membership unlocks nothing.
- **Potential:** verify app display name, icon artwork rights, age-rating answers, supported orientations, iPad layout, dynamic text/accessibility, and the legal right to distribute the art before submission.
- **Potential:** the UI contains fixed-size typography and the SpriteKit board is not yet a complete VoiceOver interaction surface. Accessibility and large-text review remain outstanding.

Apple's App Review guidance says apps without significant account-based features should allow use without login; account creation requires in-app account deletion. The current guest route follows the no-login direction, but release decisions about sign-in still need testing. No approval is guaranteed.

## Release checklist

### Essential

- [ ] Finish written rules and validate queen coverage, striker fouls, opponent coins, final coin, winning, and turn-retention scenarios.
- [ ] Test the core flow on a physical iPhone and iPad, plus the oldest supported iOS simulator; test portrait and landscape.
- [ ] Test VoiceOver, Dynamic Type, contrast, Reduce Motion, touch targets, and compact layouts; fix board-control accessibility.
- [ ] Decide whether Apple sign-in remains; keep guest access. Do not ship an email form until a real account service exists.
- [ ] Publish a privacy policy and support page with actual contact information; make the privacy page easy to open inside the app.
- [ ] Complete App Privacy disclosures from the release binary's actual data practices. Check required-reason API declarations and privacy-manifest needs.
- [ ] Confirm bundle ID, signing team, Sign in with Apple capability, production version/build, release configuration, and icon in a device archive.
- [ ] Capture final screenshots on actual supported configurations; validate exact App Store Connect sizes and all claims.
- [ ] Create the app record, verify the name, choose categories, complete age rating, copyright, review notes, and metadata.

### TestFlight and review

- [ ] Archive a Release build in Xcode; run Validate and resolve signing or asset errors.
- [ ] Upload to TestFlight and exercise install, launch, guest entry, both game modes, scoring, fouls, and restart.
- [ ] Provide reviewers the demo route (no credentials required) and clear notes that play is local and email sign-in is unavailable.
- [ ] Verify any Apple sign-in capability on a signed build using a real test Apple ID, if retained.
- [ ] Submit only with complete metadata and reachable support/privacy URLs; respond to review feedback through App Store Connect.
- [ ] After release, monitor crash reports and player feedback using services actually configured; do not claim analytics coverage before setup.

## Verification performed

- On 2026-10-27, `xcodebuild test -project CarromDuo.xcodeproj -scheme CarromDuo -destination 'platform=iOS Simulator,id=22CE6580-F203-43C9-BB9E-D1D21F5B312C' -derivedDataPath /tmp/carrom-si-derived -parallel-testing-enabled NO` built the app and test target, then passed **20 of 20 tests** on the iPhone Duo simulator running iOS 27.1.
- The test suite covers bounded launch speed, friction and stopping distance, frame-rate consistency, momentum transfer, rail rebound, swept-circle impact and anti-tunneling behavior, pocket scoring, foul rollback, queen cover, game completion, computer shot planning, and actual travel after an AI safety-shot impact.
- The first run logged SpriteKit warnings caused by attempting to set the root scene's scale and position. Those no-op assignments were removed; the final rerun passed with those warnings gone.
- Xcode still logged test-host UIKit appearance-transition and focus-cache messages while scenes were repeatedly created by unit tests. They did not fail tests; confirm whether they occur in a normal app session during manual device QA.
- No physical-device test, UI automation, accessibility audit, Release archive, signing validation, TestFlight upload, or App Store submission has been performed.

### Archive / submit procedure

1. Select **Any iOS Device (arm64)** or an equivalent generic iOS device destination in Xcode.
2. Choose **Product → Archive** using the Release configuration and the correct developer team.
3. In Organizer, validate the archive and confirm its bundle ID, version, build, icons, entitlements, and symbols.
4. Upload through Organizer to App Store Connect, process the build, and attach it to a version only after metadata and screenshots are complete.
5. Use TestFlight before App Review. Signing identities and private keys must remain in the developer's secure signing setup, not in Git.

## Prioritized roadmap

| Priority | Change | Why / likely files | Verification | Release status |
| --- | --- | --- | --- | --- |
| P1 — Essential | Complete rules table and game-over regression coverage | `CarromDuo/CarromScene.swift`, `Tests/CarromDuoPhysicsTests.swift` | Automated edge-case tests plus manual two-player/AI matches | Required |
| P1 — Essential | Publish and link privacy/support pages; finish App Privacy answers | App UI, App Store Connect | Open links on device and reconcile every disclosure with the release binary | Required |
| P1 — Essential | Accessibility and supported-device audit | `ContentView.swift`, SpriteKit board, Xcode settings | VoiceOver, text-size, landscape, iPad, small iPhone, Reduce Motion | Required |
| P1 — Essential | Decide account strategy; remove unused login or build real services and deletion | welcome/auth UI and service layer if justified | Verify every path and reviewer access | Required if login ships |
| P1 — Essential | Validate signed Release archive and TestFlight | Xcode project / App Store Connect | Archive validation and tester checklist | Required |
| P2 — High impact | Calibrate shot speed, friction, impact, and rebounds against filmed reference shots | `CarromScene.swift`, physics tests | Compare repeatable distances/angles and report measurements | Product quality |
| P2 — High impact | Capture final iPhone/iPad store screenshots | `Design/` or release asset folder | Review every image against release UI and Apple's current dimensions | Required |
| P2 — High impact | Tighten welcome and match feedback using player observations | `ContentView.swift` | Short usability sessions and layout checks | Recommended |
| P3 — Strategic | Consider online play, synced profiles, tournaments, or analytics | New architecture/services, only after product validation | Threat/privacy review and service tests | Optional |

## Official references checked

- [App information field limits](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/) — app name and subtitle rules.
- [Apple product-page guidance](https://developer.apple.com/app-store/product-page/) — name, subtitle, promotional text, and keyword limits.
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) — currently accepted iPhone/iPad dimensions.
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) — completeness, login, privacy, and account deletion guidance.

These are live Apple references; recheck them before submission because requirements can change.
