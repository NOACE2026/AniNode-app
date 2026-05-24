# 🌌 AniNode

**AniNode** is a free, open-source anime streaming client built with Flutter. Watch anime in sub or dub, track your history, browse by genre, and pick up right where you left off — on any platform.

🌐 **Live at:** https://aninode-51232.web.app

---

## ✨ Features

- **🌐 Web + Desktop** — runs in the browser (Flutter Web / CanvasKit) and natively on Windows & Linux
- **▶️ Sub / Dub switching** — per-episode mode toggle with one tap
- **🕒 Continue Watching** — watch history with per-episode progress bars and resume support
- **📺 Fullscreen player** — embed-based playback via `flutter_inappwebview`; uses the embed's own native fullscreen button on web
- **🔍 Browse & Search** — genre rows (Action, Fantasy, Comedy …), infinite scroll, filler episode markers
- **🎨 Cyberpunk UI** — dark neon aesthetic with Orbitron / Rajdhani / Share Tech Mono fonts and shimmer loading states
- **📡 AniList metadata** — scores, genres, studios, banners pulled from the AniList GraphQL API

---

## 🛠️ Tech Stack

| Layer | Library |
|---|---|
| Framework | [Flutter](https://flutter.dev) / Dart |
| State | [Riverpod](https://riverpod.dev) |
| Networking | [Dio](https://pub.dev/packages/dio) |
| WebView / Player | [flutter_inappwebview](https://pub.dev/packages/flutter_inappwebview) |
| Images | [cached_network_image](https://pub.dev/packages/cached_network_image) |
| Storage | [shared_preferences](https://pub.dev/packages/shared_preferences) |
| Fonts | Google Fonts (Orbitron, Rajdhani, Share Tech Mono) |
| Hosting | Firebase Hosting + GitHub Actions CI/CD |
| CORS proxy | Cloudflare Workers (self-hosted, free tier) |

---

## 🚀 Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.19+
- A Cloudflare Workers account (free) for CORS proxy when hosting

### Run locally

```bash
git clone https://github.com/NOACE2026/AniNode-app.git
cd AniNode-app
flutter pub get

# Desktop (Windows)
flutter run -d windows

# Web
flutter run -d chrome
```

### Build for web

```bash
flutter build web --release
firebase deploy
```

---

## 🌐 Web / CORS Notes

Flutter Web uses CanvasKit which enforces CORS on all fetch requests. The app routes API calls through a self-hosted **Cloudflare Worker** (`/?url=<encoded>`) and images through `images.weserv.nl`. To run your own instance:

1. Create a new Cloudflare Worker at [workers.cloudflare.com](https://workers.cloudflare.com)
2. Paste the proxy script below and deploy
3. Update `_corsProxy` in `lib/api/providers/anikoto_provider.dart` with your Worker URL
4. Rebuild and redeploy

<details>
<summary>Cloudflare Worker script</summary>

```js
export default {
  async fetch(request) {
    const url = new URL(request.url);
    const target = url.searchParams.get('url');
    if (!target) return new Response('Missing ?url= parameter', { status: 400 });
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, OPTIONS',
          'Access-Control-Allow-Headers': '*',
        },
      });
    }
    const proxied = await fetch(target, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Referer': 'https://anikoto.cz/',
        'Origin': 'https://anikoto.cz',
        'Accept': 'application/json, text/plain, */*',
      },
    });
    const body = await proxied.arrayBuffer();
    const headers = new Headers(proxied.headers);
    headers.set('Access-Control-Allow-Origin', '*');
    return new Response(body, { status: proxied.status, headers });
  },
};
```

</details>

---

## 📁 Project Structure

```
lib/
├── api/
│   ├── providers/
│   │   └── anikoto_provider.dart   # Anikoto API + CORS proxy
│   ├── filler_service.dart         # Jikan filler detection
│   └── scraper_api.dart            # AniList GraphQL + source resolution
├── providers/
│   ├── anime_provider.dart         # Browse / search state
│   ├── history_provider.dart       # Watch history + progress
│   └── connectivity_provider.dart  # Network status
├── screens/
│   ├── home_screen.dart            # Hero banner + genre rows
│   ├── details_screen.dart         # Anime detail + episode list
│   ├── web_player_screen.dart      # WebView player (sub/dub)
│   └── search_screen.dart
├── stubs/                          # dart:io stubs for web compilation
├── theme/
│   └── cp.dart                     # Colour palette, typography, helpers
└── main.dart
web/                                # Flutter Web assets + index.html
```

---

## 🗺️ Roadmap

- [ ] Android / iOS support
- [ ] Multiple stream sources
- [ ] AniSkip intro/outro skip
- [ ] Custom subtitle styling
- [ ] Picture-in-Picture (mobile)
- [ ] AniList login + sync watchlist

---

## 🤝 Contributing

1. Fork the repo
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Commit and push
4. Open a Pull Request

---

## 📄 License

MIT — see [`LICENSE`](LICENSE) for details.

---

**Built with ❤️ by [AmbitDev](https://github.com/NOACE2026)**
