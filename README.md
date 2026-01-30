# 🎌 Anigen

**Anigen** is a minimalist, ad-free anime streaming client for Android, built with Flutter. Inspired by the efficiency and simplicity of [`ani-cli`](https://github.com/pystardust/ani-cli), Anigen brings high-quality anime content to your mobile device with zero fluff.

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Android" />
</p>

---

## ✨ Features

- 🔍 **Powerful Search**: Find any anime title instantly using the AllAnime database with auto-search
- 📺 **Built-in High Performance Player**: Stream content directly within the app using a highly optimized internal player based on **MPV**
- 🚀 **Optimized Scrapers**: Ported logic from `ani-cli` to ensure fast and reliable stream extraction
- 🛡️ **Ad-Free Experience**: No pop-ups, no redirects—just your anime
- 🎨 **Clean UI**: Beautiful Catppuccin Mocha theme with gradient accents
- 📱 **Home Feed**: Discover top anime, popular titles, current season, and upcoming releases
- 🏷️ **Genre Browsing**: Explore anime by categories with top 50 anime per genre
- ℹ️ **Detailed Info**: View comprehensive anime information from MyAnimeList
- 📜 **Recent Anime**: Quick access to your recently watched anime with thumbnails
- 🎬 **Custom Video Controls**: Intuitive player with speed control, quality selection, and progress tracking

---

## 📖 Usage

### Home Screen
- Browse curated lists: **Top Anime** and **Popular**
- Check out **Current Season** and **Upcoming** anime
- Explore anime by **Genre Categories** (16 handpicked genres)
- Tap any anime to view detailed information

### Search
- Type to instantly search with auto-complete
- View recent anime with thumbnails
- Select anime to see episodes

### Player
- Tap to show/hide controls
- Double tap left/right to skip ±10 seconds
- Adjust playback speed (0.5x to 2x)
- Change video quality on-the-fly
- Resume from where you left off

---

## 🛠️ Technical Stack

- **Flutter 3.10.7** with Dart
- **media_kit** for MPV-based video playback
- **Jikan API** for MyAnimeList data integration
- **AllAnime GraphQL API** for streaming links
- **shared_preferences** for local data persistence
- **Catppuccin Mocha** color scheme with JetBrains Mono font

---

## 🤝 Credits

- **[ani-cli](https://github.com/pystardust/ani-cli)**: For the inspiration and the robust scraping logic
- **[AllAnime](https://allanime.day)**: For the comprehensive anime database and streaming links
- **[Jikan API](https://jikan.moe/)**: For MyAnimeList data integration
- **[media_kit](https://github.com/alexmercerind/media_kit)**: For the high-performance MPV-based playback engine
- **[Catppuccin](https://github.com/catppuccin/catppuccin)**: For the beautiful color scheme

---

## ⚠️ Disclaimer

Anigen does not host any content. It is a scraper that finds links from publicly available sources on the internet. Please use this application responsibly and support the official releases of the anime you love.

---

<p align="center">Made with ❤️ for the Anime Community</p>
