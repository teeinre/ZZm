# ZZmore Store API Integration Guide

## Overview
This comprehensive guide covers how to integrate the ZZmore Store Flutter mobile app with the zzmore.store WordPress/WooCommerce e-commerce platform.

---

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Authentication Setup](#authentication-setup)
3. [Endpoint Configuration](#endpoint-configuration)
4. [Data Synchronization](#data-synchronization)
5. [Error Handling](#error-handling)
6. [Best Practices](#best-practices)

---

## Prerequisites

### WordPress Plugins
Ensure these plugins are installed and active on zzmore.store:
1. **WooCommerce** - Core e-commerce functionality
2. **JWT Authentication for WP REST API** - For secure token-based authentication
   - Download: https://wordpress.org/plugins/jwt-authentication-for-wp-rest-api/
3. **WooCommerce REST API** - Enabled via WooCommerce > Settings > Advanced > REST API

### Server Requirements
- PHP 7.4 or higher
- WordPress 5.6 or higher
- WooCommerce 5.0 or higher
- HTTPS enabled (required for JWT and payment processing)

---

## Authentication Setup

### Step 1: Generate WooCommerce API Keys
1. Go to **WooCommerce > Settings > Advanced > REST API**
2. Click **Add Key**
3. Fill in details:
   - **Description**: ZZmore Mobile App
   - **User**: Select admin or shop manager
   - **Permissions**: Read/Write
4. Click **Generate API Key**
5. **IMPORTANT**: Save your Consumer Key and Consumer Secret immediately - you won't see them again!

### Step 2: Configure JWT Authentication
1. Install and activate "JWT Authentication for WP REST API" plugin
2. Add this to your `wp-config.php`:
   ```php
   define('JWT_AUTH_SECRET_KEY', 'your-secret-key-here'); // Use a strong secret key
   define('JWT_AUTH_CORS_ENABLE', true);
   ```
3. Save and refresh permalinks (Settings > Permalinks > Save Changes)

### Step 3: Flutter App Configuration
Update `lib/constants/api_constants.dart`:
```dart
class ApiConstants {
  static const String baseUrl = 'https://zzmore.store/wp-json';
  static const String wpApiBase = '$baseUrl/wp/v2';
  static const String wcApiBase = '$baseUrl/wc/v3';
  static const String authEndpoint = '$baseUrl/jwt-auth/v1/token';
  static const String tokenValidateEndpoint = '$baseUrl/jwt-auth/v1/token/validate';
  
  // WooCommerce keys (for server-side validation only - never expose in app!)
  // Consumer Key and Secret should be stored securely on a backend server
}
```

### Step 4: Authentication Flow in Flutter
1. **Login**: User enters username and password
2. **Request Token**: `POST /jwt-auth/v1/token`
3. **Store Token**: Securely save token using `flutter_secure_storage`
4. **Use Token**: Include `Authorization: Bearer <token>` in all protected requests
5. **Validate Token**: Periodically validate token freshness with `token/validate` endpoint
6. **Logout**: Clear token from storage and reset user state

---

## Endpoint Configuration

### Products API
| Method | Endpoint | Description | Auth Required |
|--------|----------|-------------|---------------|
| GET    | /wc/v3/products | Get all products | No |
| GET    | /wc/v3/products/{id} | Get single product | No |
| GET    | /wc/v3/products/categories | Get categories | No |
| POST   | /wc/v3/products | Create product | Yes |

### Orders API
| Method | Endpoint | Description | Auth Required |
|--------|----------|-------------|---------------|
| GET    | /wc/v3/orders | Get user orders | Yes |
| POST   | /wc/v3/orders | Create new order | Yes |
| GET    | /wc/v3/orders/{id} | Get order details | Yes |

### Customers API
| Method | Endpoint | Description | Auth Required |
|--------|----------|-------------|---------------|
| GET    | /wc/v3/customers/{id} | Get customer profile | Yes |
| PUT    | /wc/v3/customers/{id} | Update customer profile | Yes |

### Example Usage in Flutter
```dart
// Fetching products
final apiService = ApiService();
final products = await apiService.getProducts(page: 1, perPage: 10);

// Fetching categories
final categories = await apiService.getCategories();
```

---

## Data Synchronization

### Local Caching Strategy (Hive)
The app uses Hive for offline-first caching:
1. **Products**: Cached in `products` box
2. **Categories**: Cached in `categories` box
3. **Cart**: Cached in `cart` box
4. **Settings**: Cached in `settings` box

### Synchronization Flow
1. **Online**:
   - Make API request
   - If successful, update local cache
   - Update UI with fresh data
   - Save response to Hive for offline use
2. **Offline**:
   - Fall back to local Hive cache
   - Show cached data
3. **Error handling**: Show error message and try cached data if available

### Background Sync (Optional)
For periodic background synchronization:
```dart
// Use workmanager package for background tasks
// Refresh products/categories periodically
```

---

## Error Handling

### Error Types & Responses
| Error Type | Description | Action |
|------------|-------------|--------|
| 200 OK | Request successful | Return data |
| 401 Unauthorized | Invalid token | Log user out |
| 404 Not Found | Resource not found | Show not found error |
| 500 Internal Server Error | Server issue | Show generic error, retry later |

### Custom Exception Classes
The app includes:
- `ApiException` - General API error
- `UnauthorizedException` - Authentication error
- `NotFoundException` - Resource not found

### Error UI Feedback
- Show SnackBar with error message
- Fall back to cached data when available
- Provide retry button when network is available

---

## Best Practices

1. **Security**:
   - Never store API keys in client-side code
   - Use HTTPS for all requests
   - Store auth tokens securely with `flutter_secure_storage`
   - Implement token refresh mechanism

2. **Performance**:
   - Cache data locally for offline access
   - Use pagination for large datasets (default per_page=10)
   - Optimize image loading with `cached_network_image`

3. **Error Handling**:
   - Provide meaningful error messages to users
   - Retry failed requests when network becomes available
   - Fall back to cached data when offline

4. **Testing**:
   - Write unit tests for API service and providers
   - Write integration tests for complete flows
   - Test offline functionality

---

## Troubleshooting

### Common Issues
1. **CORS Errors**: Ensure `JWT_AUTH_CORS_ENABLE` is true in wp-config.php
2. **Authentication Errors**: Check JWT secret key and plugin configuration
3. **Data Not Syncing**: Verify Hive is initialized properly and caching is working

### Debugging
- Enable debug logging in `ApiService`
- Use Flutter DevTools to inspect network requests and Hive database
- Check server logs on zzmore.store for errors

---

## Appendix: Sample API Requests

### Login Request
```http
POST /wp-json/jwt-auth/v1/token
Content-Type: application/json

{
  "username": "user@example.com",
  "password": "password123"
}
```

### Get Products Request
```http
GET /wp-json/wc/v3/products?per_page=10&page=1
Authorization: Bearer <token>
```

### Create Order Request
```http
POST /wp-json/wc/v3/orders
Authorization: Bearer <token>
Content-Type: application/json

{
  "payment_method": "bacs",
  "payment_method_title": "Direct Bank Transfer",
  "set_paid": false,
  "billing": { ... },
  "shipping": { ... },
  "line_items": [ ... ]
}
```
