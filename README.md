<div align="center">

# Voltspot

**iOS app for locating EV and agricultural-drone charging stations across Thailand.**

Built on Clean Architecture, SwiftUI, and OCPP 1.6-J.

[![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-blue)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange)](https://swift.org)
[![Xcode](https://img.shields.io/badge/Xcode-16%2B-1575F9)](https://developer.apple.com/xcode/)
[![License](https://img.shields.io/badge/license-TBD-lightgrey)](#license)

</div>

> **Status — early scaffold.** UI, persistence, and the OCPP layer are wired up with mock data. The backend Central System and real station data are intentionally out of scope at this stage.

> **Naming.** `Voltspot` is a working title and may change. The display name is centralised in [`AppConfig.appName`](Voltspot/App/AppConfig.swift) and resolves through every UI surface — rebranding is a single-line edit.

---

## Highlights

- 🇹🇭 **Thai-first** — primary language `th-TH`, English fallback, THB currency, default map region centred on Thailand.
- 🔀 **Dual user roles** — Consumer (driver / drone operator) and Partner (station owner). Selected on first launch and persistent.
- 🔌 **OCPP 1.6-J data layer** — hand-written Codable models matching the official JSON schemas, plus a WebSocket transport ready for a future Central-System monitor.
- 🧱 **Clean Architecture (MVVM)** — strict layering, Swift 6 strict concurrency, easy to unit-test.
- 🪪 **Single-source brand** — every visible reference to the app name resolves through one constant.

---

## Screens

```
Sign in / Sign up
       ↓
Role Selection ─────────────────────────────────┐
       ↓                                        │
Consumer (3 tabs)                  Partner (4 tabs)
├─ Find       (MapKit station finder)            ├─ Dashboard  (KPIs + recent activity)
├─ Session    (active charging session)          ├─ Stations   (operator-owned list)
└─ Profile    (switch role / sign out)           ├─ Earnings   (gross / commission / net)
                                                 └─ Profile
```

A more detailed UX brief — including localisation keys, mock data, and design tokens — lives in the docs folder of the design system tooling.

---

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│  Presentation                                              │
│   • SwiftUI views, @Observable view models, @MainActor     │
└──────────────────┬───────────────────────────────────┬─────┘
                   ▼                                   ▼
        ┌────────────────────┐                 ┌─────────────┐
        │      Domain        │                 │    Core     │
        │  Entities          │                 │ Localization│
        │  Repositories (P)  │                 │     Map     │
        │  Use Cases         │                 └─────────────┘
        └──────────▲─────────┘
                   │
        ┌──────────┴───────────────────────────────────────┐
        │                    Data                          │
        │   Mock repositories │ Keychain / UserDefaults    │
        │              OCPP 1.6-J transport                │
        └──────────────────────────────────────────────────┘
```

- **Domain** imports only `Foundation` (and `CoreLocation`). No UIKit / SwiftUI / networking. Pure business types.
- **Data** implements `Domain/Repositories/*` protocols. Swap mocks for real backends without touching the UI.
- **Presentation** holds protocol-typed dependencies — never concrete repositories.

`AppSession` (an `@Observable` class injected at the app root) is the single source of truth for routing. `RootView` switches on `(user, role)`:

| State | Screen |
|---|---|
| `(nil, _)` | `AuthView` |
| `(user, nil)` | `RoleSelectionView` |
| `(user, .consumer)` | `ConsumerTabView` |
| `(user, .partner)` | `PartnerTabView` |

---

## Project layout

```
Voltspot/
├── Voltspot.xcodeproj/      # Xcode 16+ uses a synchronized root group — files auto-discover
├── Voltspot/
│   ├── App/                      # Entry point, AppConfig, AppSession, RootView
│   ├── Resources/                # Localizable.xcstrings (th + en)
│   ├── Domain/
│   │   ├── Entities/             # User, UserRole, Station, Connector, Tariff, ChargingSession
│   │   ├── Repositories/         # Protocols (AuthRepository, StationRepository, …)
│   │   └── UseCases/             # SignIn, SignUp, SelectRole, FindNearbyStations
│   ├── Data/
│   │   ├── Auth/                 # MockAuthRepository
│   │   ├── Stations/             # MockStationRepository
│   │   ├── Persistence/          # KeychainStore, RolePreferenceStore
│   │   └── OCPP/                 # 1.6-J wire envelope, message models, WebSocketManager, OCPPClient
│   ├── Presentation/
│   │   ├── Common/               # BrandHeader, ThaiBahtText, LoadingView
│   │   ├── Authentication/       # AuthView, RoleSelectionView (+ view models)
│   │   ├── Consumer/             # StationFinder, StationDetail, Session, Profile
│   │   └── Partner/              # Dashboard, MyStations, Earnings, Profile
│   └── Core/
│       ├── Localization/         # CurrencyFormatter (THB)
│       └── Map/                  # ThailandRegion (default map region)
└── VoltspotTests/
    ├── OCPPCodableTests.swift
    └── RolePreferenceStoreTests.swift
```

---

## Domain rules worth knowing

| Topic | Rule |
|---|---|
| **Brand** | The literal app name lives only in `AppConfig.appName`. Every UI surface resolves through it. |
| **Money** | Tariffs are stored as integer **satang** (`pricePerKWhSatang`, `sessionFeeSatang`); converted to `Decimal` baht at the display boundary. No `Double` for money. |
| **Concurrency** | Views & view models are `@MainActor`. `MockAuthRepository`, `WebSocketManager`, and `OCPPClient` are `actor`s. `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated` overrides Xcode 16's MainActor-by-default. |
| **Persistence** | Auth tokens → Keychain. Role preference → UserDefaults. The UI never writes to either directly — it goes through `AppSession`. |

---

## OCPP 1.6-J

The iOS app behaves as a **client of a backend Central System**, not as a charge point. The OCPP layer exists so that:

1. Shared types are available app-wide.
2. A future Partner diagnostic view can connect to a backend WebSocket and observe live OCPP traffic.

### Implemented message pairs

| Action | Request | Response |
|---|---|---|
| BootNotification | ✅ | ✅ |
| Heartbeat | ✅ | ✅ |
| StatusNotification | ✅ | ✅ |
| Authorize | ✅ | ✅ |
| StartTransaction | ✅ | ✅ |
| StopTransaction | ✅ | ✅ |
| MeterValues | ✅ | ✅ |
| RemoteStartTransaction | ✅ | ✅ |
| RemoteStopTransaction | ✅ | ✅ |
| DataTransfer | ✅ | ✅ |

Codable models are hand-written from the official JSON schemas. The `chargingProfile` nested type on `RemoteStartTransaction` is intentionally omitted from the scaffold.

### Status

| Component | Status |
|---|---|
| Version detection (1.6-J, subprotocol `ocpp1.6`) | Done |
| Heterogeneous-array wire envelope (`[2/3/4, …]`) | Done — `OCPPEnvelope` |
| `WebSocketManager` (URLSessionWebSocketTask + subprotocol header) | Done |
| `OCPPClient` (uniqueId correlation, async call/reply) | Done |
| Auto-reconnect with backoff | Manual reconnect only |
| Charging-profile / SmartCharging models | Out of scope |
| Wired into Partner UI | Pending |

---

## Requirements

- macOS 14+
- Xcode 16 (uses `PBXFileSystemSynchronizedRootGroup`, the file-sync feature)
- iOS 17+ deployment target
- Swift 6.0

No third-party dependencies. No package manager.

---

## Build & run

```bash
git clone https://github.com/sirawitchpoon/voltspot.git
cd voltspot
open Voltspot.xcodeproj
```

Pick an iPhone simulator (iOS 17+) and press ⌘R.

### From the command line

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Voltspot.xcodeproj \
  -scheme Voltspot \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

> The synchronized root group means **new files appear in the target automatically** — just drop a `.swift` file under `Voltspot/Voltspot/...` and Xcode will pick it up. Don't hand-edit `project.pbxproj`.

---

## Rebranding in one edit

Open [`Voltspot/App/AppConfig.swift`](Voltspot/App/AppConfig.swift) and change:

```swift
enum AppConfig {
    static let appName: String = "Voltspot"   // ← edit this
    …
}
```

Verify there is exactly one match in the source tree:

```bash
grep -rn '"Voltspot"' Voltspot --include='*.swift'
```

---

## Localisation

- All user-visible strings live in [`Resources/Localizable.xcstrings`](Voltspot/Resources/Localizable.xcstrings).
- Currency formatting goes through [`Core/Localization/CurrencyFormatter.swift`](Voltspot/Core/Localization/CurrencyFormatter.swift) — reads `AppConfig.currencyCode` (`THB`) and `AppConfig.currencyLocaleIdentifier` (`th_TH`).
- To add a language: append the locale to `AppConfig.supportedLanguages`, add it to `knownRegions` in the project, and translate the entries in the `.xcstrings` catalog.

---

## What's deliberately out of scope

- Real authentication (Firebase / Supabase / custom REST) — swap `MockAuthRepository` for a concrete `AuthRepository` implementation; call sites stay unchanged.
- Real station data — swap `MockStationRepository` similarly.
- Background OCPP traffic / push notifications.
- Smart-charging profiles.
- Brand assets (icons, colours, splash). The tint defaults to system blue while branding is finalised.

---

## License

License terms have not been finalised. Treat this repository as **all rights reserved** until a license file is added.

---

<div align="center">

Made with care for Thailand's EV and agri-drone ecosystem.

</div>
