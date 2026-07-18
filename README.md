# ZZMore Store Mobile App

A Flutter mobile application for zzmore.store - WooCommerce powered marketplace.

## Features

- 🔐 **Authentication**: JWT based authentication for protected API endpoints
- 📦 **Products**: Browse products from WordPress/WooCommerce REST API
- 🛒 **Cart**: Add/remove items, manage quantities
- 📱 **Responsive UI**: Beautiful, responsive design based on provided React template
- 💾 **Offline Caching**: Hive-based data caching for offline access
- 📄 **Pagination**: Infinite scroll with pagination support
- 🛡️ **Error Handling**: Comprehensive error handling for network failures
- 🧪 **Testing**: Unit and integration tests

## Tech Stack

- **Flutter**: Cross-platform mobile framework
- **Provider**: State management
- **Hive**: Local storage/caching
- **http**: REST API communication
- **flutter_secure_storage**: Secure storage for auth tokens
- **google_fonts**: Typography

## Getting Started

### Prerequisites

- Flutter SDK (>=3.0.0)
- Dart SDK
- Android Studio / VS Code

### Installation

1. Clone the repository
2. Install dependencies:

```bash
flutter pub get
```

3. Run the app:

```bash
flutter run
```

## Configuration

Update API constants in `lib/constants/api_constants.dart`:

```dart
static const String baseUrl = 'https://zzmore.store/wp-json';
```

## Project Structure

```
lib/
├── cache/              # Hive cache service
├── constants/          # App constants (colors, API)
├── models/             # Data models
├── providers/          # State management
├── screens/            # UI screens
├── services/           # API and storage services
├── widgets/            # Reusable widgets
└── main.dart           # App entry point
```

## API Integration

### WordPress REST API

- Products endpoint: `/wp-json/wc/v3/products`
- Categories endpoint: `/wp-json/wc/v3/products/categories`

### Authentication

The app uses JWT authentication. Make sure the JWT Authentication for WP REST API plugin is installed on your WordPress site.

## Building for Production

### Android

```bash
flutter build apk --release
```

### iOS

```bash
flutter build ios --release
```

## App Store and Play Store Guidelines

- **Android**: Follow Material Design 3 guidelines, target SDK 34+
- **iOS**: Follow Human Interface Guidelines, support latest iOS versions
- **Accessibility**: WCAG 2.1 compliant with proper semantic labels

## Running Tests

```bash
# Unit tests
flutter test test/unit_test/

# Integration tests
flutter test test/integration_test/
```

## License

MIT
