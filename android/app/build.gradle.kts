import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// مفتاح التوقيع: من android/key.properties (محلياً) أو من متغيرات البيئة (GitHub Actions).
// بدونه يُوقَّع بمفتاح التصحيح (للتجربة فقط).
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun signingValue(name: String, env: String): String? =
    keyProps.getProperty(name) ?: System.getenv(env)?.takeIf { it.isNotBlank() }
val releaseStoreFile = signingValue("storeFile", "VORTEX_KEYSTORE_PATH")

android {
    namespace = "app.vortex.vortex"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // مطلوب لمكتبة الإشعارات المحلية
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "app.vortex.vortex"
        // الكاميرا (mobile_scanner) والبصمة تحتاج أندرويد 7 فأعلى
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseStoreFile != null) {
            create("release") {
                storeFile = file(releaseStoreFile)
                storePassword = signingValue("storePassword", "VORTEX_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "VORTEX_KEY_ALIAS") ?: "vortex"
                keyPassword = signingValue("keyPassword", "VORTEX_KEY_PASSWORD")
                    ?: signingValue("storePassword", "VORTEX_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseStoreFile != null) signingConfigs.getByName("release")
                            else signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
