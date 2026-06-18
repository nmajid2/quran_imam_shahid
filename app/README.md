# App — Quran Imam Shahid (Flutter)

Cross-platform (Android / iOS / Web) client. Talks **only** to the gateway
([../gateway](../gateway)) — never to AI/speech providers directly, and never holds
their keys.

## Prerequisites

Flutter SDK ≥ 3.22 (not installed in this environment yet):
<https://docs.flutter.dev/get-started/install>

## Run

Start the gateway first (see [../gateway/README.md](../gateway/README.md)), then:

```bash
cd app
flutter pub get

# Point the app at your gateway + device token:
flutter run \
  --dart-define=GATEWAY_URL=http://localhost:8077 \
  --dart-define=DEVICE_TOKEN=<your-device-token>

# Web:
flutter run -d chrome --dart-define=GATEWAY_URL=http://localhost:8077 --dart-define=DEVICE_TOKEN=<token>
```

Tests:

```bash
flutter test
```

## Structure

```
lib/
├── main.dart                     # app entry, theme, locales (fa/en/nl)
├── core/
│   ├── config.dart               # gateway URL + device token (dart-define)
│   ├── api_client.dart           # the ONLY thing that calls the gateway
│   ├── intents.dart              # client-side intent allow-list (typed handlers)
│   ├── providers.dart            # Riverpod providers
│   └── theme.dart                # calm light/dark theme, Arabic text style
├── data/models/surah.dart        # Surah / Ayah models
└── features/
    ├── surah_list/               # browse surahs, switch language
    └── reader/                   # read ayat (Arabic RTL + translation) + tafsir sheet
```

## What works now (Phase 1 slice)

- Browse surahs and read ayat: **Arabic (RTL) + fa/en/nl translation**, language switch.
- Per-ayah **tafsir** bottom sheet with **source citations** and a confidence chip
  ("grounded" / "insufficient — consult a scholar").

## Next (per ../IMPLEMENTATION_PLAN.md)

- Ayah audio playback with synced highlight; last-read position in local SQLite.
- Voice round-trip (record → `/v1/voice` → typed intent handlers).
- Then Q&A chat, recitation coaching, and the **Hifz** memorization tracker.
