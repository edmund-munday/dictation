plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.edmundmunday.dictation.keyboard"
    compileSdk = 35

    ndkVersion = "27.2.12479018"

    defaultConfig {
        applicationId = "com.edmundmunday.dictation.keyboard"
        minSdk = 34
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    sourceSets.getByName("main").assets.srcDir("../bench")

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
        unitTests.isReturnDefaultValues = true
    }
}

val fetchWhisperCpp = tasks.register<Exec>("fetchWhisperCpp") {
    val dest = file("../third_party/whisper.cpp")
    onlyIf { !dest.resolve("CMakeLists.txt").isFile }
    commandLine(
        "git",
        "clone",
        "--depth",
        "1",
        "--branch",
        "v1.9.5",
        "https://github.com/ggml-org/whisper.cpp.git",
        dest.absolutePath,
    )
}

tasks.configureEach {
    if (name.contains("configureCMake") || name.contains("externalNativeBuild") || name.contains("buildCMake")) {
        dependsOn(fetchWhisperCpp)
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.14.1")
}
