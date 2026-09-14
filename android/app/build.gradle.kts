import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val fallbackKeystorePropertiesFile = rootProject.file(
    "../../fmi-branding-kit/android-keystore/key.properties",
)
val activeKeystorePropertiesFile = when {
    keystorePropertiesFile.exists() -> keystorePropertiesFile
    fallbackKeystorePropertiesFile.exists() -> fallbackKeystorePropertiesFile
    else -> null
}
if (activeKeystorePropertiesFile != null) {
    keystoreProperties.load(activeKeystorePropertiesFile.inputStream())
}

android {
    namespace = "io.instance001.chatty_venture"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.instance001.chatty_venture"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters += listOf("arm64-v8a")
        }

        externalNativeBuild {
            cmake {
                cppFlags += listOf("-std=c++17")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    signingConfigs {
        create("release") {
            if (activeKeystorePropertiesFile != null) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                val configuredStoreFile = keystoreProperties["storeFile"] as String
                val localStoreFile = rootProject.file(configuredStoreFile)
                val fallbackStoreFile = activeKeystorePropertiesFile.parentFile.resolve(
                    configuredStoreFile,
                )
                storeFile = if (localStoreFile.exists()) {
                    localStoreFile
                } else {
                    fallbackStoreFile
                }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (activeKeystorePropertiesFile != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
