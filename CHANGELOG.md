# Changelog

All notable changes to ZZmore Store mobile app.

---

## [3.2.0] — 2026-08-19

### Added
- **In-app OTP password reset**: Replaced the email reset-link flow with a
  time-limited (10-minute) one-time password sent to the user's registered
  email, keeping the whole password change inside the app.
- **OTP verification screen**: New in-app screen to enter the emailed code,
  choose a new password, and confirm it, with client-side match validation.
- **Server-side OTP validation**: REST endpoints (`request-otp`, `verify-otp`)
  validate the code's value, expiration, and email match, and enforce password
  strength (minimum 8 characters with a letter and a number).
- **Post-reset success state**: Confirmation message with a "Login" button to
  return to sign-in after a successful password change.
- **Password autofill**: Login and reset forms now expose autofill hints so
  saved credentials from Google Password Manager can fill and save passwords.

### Changed
- Bumped version to 3.2.0+5.

---

## [1.0.2] — 2026-08-02

### Added
- **Vendor Dashboard Persistence**: All dashboard data (stats, orders, products,
  withdrawals, coupons, reviews, announcements, balance) is now persisted to
  Hive local storage. Dashboard loads instantly from cache on app restart and
  silently refreshes in the background.
- **Inventory Levels**: Real-time inventory summary on vendor dashboard showing
  in-stock, out-of-stock, and low-stock product counts.
- **Customer Engagement Stats**: Average rating, review count, and completed
  orders displayed on vendor dashboard.
- **Performance Report**: Fulfillment rate, average order value, pending orders,
  and total withdrawals panel on vendor dashboard.
- **Subscription Support**: Full WooCommerce Subscriptions integration —
  subscription product detection via meta data parsing, tiered billing interval
  selector (weekly/monthly/annual), trial badge, one-time vs recurring toggle,
  and interval-aware cart pricing.
- **`.env.template`**: Environment variable template for new contributors.

### Fixed
- **Vendor 126 Global Exclusion**: Vendor ID 126 (`vendors/126`) is now
  completely hidden across all surfaces:
  - Public vendor list (VendorProvider.filteredVendors)
  - Product catalog (ProductsProvider._filterExcluded)
  - Search results (SearchResultsPage)
  - Category browse (CategoryProductsPage)
  - Product detail page (guard with "Product Not Available" UI)
  - Vendor profile page (init guard before any data load)
  - Livestream add-to-cart (all three livestream screens)
  - Direct URL / deep-link navigation (navigation guards)
- **Vendor Profile Product Scoping**: Products shown on a vendor's profile are
  now strictly scoped by vendor ID + vendor name match, preventing cross-vendor
  product leakage from API fallbacks.
- **iOS Code Signing**: Fixed Codemagic workflow — added missing
  `keychain add-certificates` and `xcode-project use-profiles` commands to
  complete the signing chain.
- **iOS Deployment Target**: Bumped from 13.0 to 15.0 to match Firebase's
  minimum requirement.
- **Codemagic IPA Packaging**: Fixed fallback packaging — unsigned `.app`
  bundles are now properly zipped into `.ipa` containers.
- **R8 Build**: Added `-dontwarn` rules for Google Play Core classes (deferred
  components not used by this app); disabled `android.enableR8.fullMode` for
  local dev builds (re-enable for Play Store).
- **Android SDK Target**: Bumped `compileSdk` / `targetSdk` from 35 to 36 for
  Google Play compliance (deadline: Aug 31, 2026).
- **Edge-to-Edge Deprecation**: Removed deprecated `setStatusBarColor`,
  `setNavigationBarColor`, and related APIs; migrated to native edge-to-edge
  with transparent system bars in themes.

### Changed
- **Vendor Dashboard UI**: Added three new reporting sections (Inventory,
  Engagement, Performance) with card-based layout.
- **ProGuard/R8 Rules**: Added keep rules for Flutter engine, Firebase, and
  Kotlin coroutines.
- **dSYM Artifacts**: Tightened Codemagic glob from broad DerivedData pattern
  to `build/ios/archive/Runner.xcarchive/dSYMs/*.dSYM`.

---

## [1.0.1] — 2026-07-16

### Added
- Initial public release
- WooCommerce product catalog with infinite scroll
- Vendor store profiles with Dokan integration
- JWT authentication with WordPress
- Livestream support (YouTube, Facebook, HLS)
- Shopping cart with local persistence
- Offline product caching via Hive
- Material Design 3 with Adire-inspired theme
