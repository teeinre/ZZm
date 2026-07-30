import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Load keystore properties for release signing
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "store.zzmore.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "store.zzmore.app"
        // Google Play requires targetSdk >= 34 for new apps as of Aug 2025
        minSdk = 24
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName

    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            isDebuggable = true
        }

        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // Enable R8 code shrinking, obfuscation, and optimization
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )

            isDebuggable = false
            isCrunchPngs = true

            // Generate native debug symbols for Play Console crash reporting.
            // Using "symbol_table" (not "full") to avoid NDK 28 stripping issues
            // while still providing enough information for ANR and crash analysis.
            ndk {
                debugSymbolLevel = "symbol_table"
            }
        }
    }

    // AAB bundle configuration – Play App Signing & dynamic delivery
    bundle {
        // Language splitting – Flutter handles i18n at the Dart layer;
        // disabled to avoid removing locale resources the framework needs.
        language {
            enableSplit = false
        }
        // Density splitting – serves only the device's screen-density resources
        density {
            enableSplit = true
        }
        // ABI splitting – serves only the device's native-code architecture
        abi {
            enableSplit = true
        }
    }

    // Exclude Dokan plugin directories from build processing
    aaptOptions {
        ignoreAssetsPattern = "!dokan-lite*:!dokan-pro*"
    }

    // Recommended compiler flags for release builds
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
    }
}

// Core library desugaring – required for java.time APIs on older API levels
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
