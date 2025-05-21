plugins {
    id("com.android.application")

    // ✅ Google services Gradle plugin
    id("com.google.gms.google-services")

    id("kotlin-android")

    // ✅ Flutter plugin must be last
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.upay"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.upay"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")

    // ✅ Required for desugaring modern Java APIs
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // ✅ Firebase BoM (Bill of Materials) to manage Firebase versions
    implementation(platform("com.google.firebase:firebase-bom:33.13.0"))

    // ✅ Add Firebase dependencies below — version is managed by BoM
    // e.g.
    // implementation("com.google.firebase:firebase-auth")
    // implementation("com.google.firebase:firebase-firestore")

}
