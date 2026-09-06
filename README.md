# ZZMore Store Mobile App

A Flutter mobile application for zzmore.store - WooCommerce powered marketplace.

## Features

- 🔐 **Authentication**: JWT based authentication for protected API endpoints
- 📦 **Products**: Browse products from WordPress/WooCommerce REST API
- 📅 **Service Booking**: Browse bookable services, pick a slot, and confirm bookings
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

## Service Booking Integration

The app integrates the **WooCommerce Bookings** plugin (see `woocommerce-bookings/`) to offer end-to-end service booking.

### How it works

1. **Browse services** — the Explore tab has a `Services` filter chip that queries bookable products via `GET /wp-json/wc/v3/products?type=booking`.
2. **Choose a slot** — the `BookingSlotPickerScreen` fetches availability from `GET /wp-json/wc-bookings/v1/products/slots?product_ids={id}` and lets the customer pick a date + time.
3. **Confirm** — the selected slot is stored on the `CartItem` (`bookingDate`, `bookingResourceId`) and synced to the server cart with the plugin's expected `booking_configuration` payload:
   ```json
   { "date": "2026-08-23 14:00:00", "resource_id": 12 }
   ```
4. **Checkout** — the WooCommerce Bookings Store API extension validates the slot (rejecting double bookings with a `409`) and creates the booking on order completion.

### Key files

- `lib/models/booking_slot.dart` — availability slot model.
- `lib/models/product.dart` — bookable product fields (`bookingDuration`, `bookingDurationUnit`, `bookingCost`, `hasResources`, …).
- `lib/models/cart_item.dart` — booking slot persistence + Store API `booking_configuration` mapping.
- `lib/services/api_service.dart` — `getBookingSlots()` and Store API `addToStoreCart(bookingConfiguration: …)`.
- `lib/screens/booking_slot_picker_screen.dart` — date/time slot picker UI.
- `lib/screens/product_detail_screen.dart` — "Book Now" flow for `type=booking` products.
- `lib/screens/explore_screen.dart` — `Services` browse filter.
- `lib/providers/cart_provider.dart` — wires booking configuration through local + server cart sync.

### Server-side requirements

- WooCommerce Bookings plugin active on the WordPress site.
- The plugin's REST (`wc-bookings/v1`) and Store API (`wc/store/v1`) routes must be reachable.

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
