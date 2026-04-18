# 🌌 AniNode

![AniNode Banner](https://raw.githubusercontent.com/invins2003/AniNode-app/main/assets/images/banner.png)

**AniNode** is a premium, high-performance anime streaming client built with Flutter. It combines a sleek, modern interface with the power of native media playback, providing a seamless experience across Mobile (Android/iOS) and Desktop (Windows/Linux).

---

## ✨ Features

- **🚀 Native Performance**: Leveraging `media_kit` for blistering fast, hardware-accelerated video playback.
- **📅 Stay Updated**: Real-time synchronization with **AniList** for trending, popular, and seasonal anime.
- **🕒 Continue Watching**: Robust watch history tracking with progress bars for every episode.
- **📥 Offline Mode**: Intelligent connectivity detection that automatically switches to your downloads when you're off the grid.
- **🔍 Deep Discovery**: Advanced search capabilities and filtered categories to find exactly what you're looking for.
- **📟 Terminal Access**: Built-in developer terminal for advanced insights and stream debugging.
- **🎨 Premium UI**: A curated dark aesthetic featuring the *Outfit* typeface, smooth shimmer loading states, and dynamic hero sliders.
- **💻 Truly Cross-Platform**: Optimized for Android, iOS, Windows, and Linux.

---

## 🛠️ Tech Stack

- **Core**: [Flutter](https://flutter.dev) & [Dart](https://dart.dev)
- **State Management**: [Riverpod](https://riverpod.dev) (Functional & Reactive)
- **Networking**: [Dio](https://pub.dev/packages/dio) & [GraphQL Flutter](https://pub.dev/packages/graphql_flutter)
- **Playback Engine**: [Media Kit](https://github.com/alexmercerind/media_kit) (FFmpeg based)
- **Database**: [Shared Preferences](https://pub.dev/packages/shared_preferences) for configuration and local state.
- **Styling**: Google Fonts (Outfit), Custom Shimmers, and Glassmorphic elements.

---

## 🚀 Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (v3.9.2 or higher)
- [FFmpeg](https://ffmpeg.org/) (Required for `media_kit` native playback on desktop)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/invins2003/AniNode-app.git
   cd aninode_mobile
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Platform Setup**
   - **Android/iOS**: Standard Flutter setup.
   - **Windows/Linux**: Ensure you have the necessary build tools and FFmpeg installed.
     ```bash
     # For Windows MSIX build
     flutter pub run msix:create
     ```

4. **Run the application**
   ```bash
   flutter run
   ```

---

## 📸 Screenshots

| Home Screen | Details View | Video Player |
| :---: | :---: | :---: |
| ![Home](https://raw.githubusercontent.com/invins2003/AniNode-app/main/assets/screenshots/home.png) | ![Details](https://raw.githubusercontent.com/invins2003/AniNode-app/main/assets/screenshots/details.png) | ![Player](https://raw.githubusercontent.com/invins2003/AniNode-app/main/assets/screenshots/player.png) |

---

## 🗺️ Roadmap

- [ ] Support for multiple scrapers/sources.
- [ ] AniSkip integration for auto-skipping intros.
- [ ] Custom subtitle styling options.
- [ ] Picture-in-Picture (PiP) mode for mobile.
- [ ] TV/Landscape optimized UI.

---

## 🤝 Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📄 License

Distributed under the MIT License. See `LICENSE` for more information.

---

**Built with ❤️ by [AmbitDev](https://github.com/invins2003)**
