plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// 体积控制：只打「本次构建目标」的那一条 ABI。
//
// 内置离线语音用 sherpa-onnx，它的 AAR 给**每条 ABI** 各带一份 onnxruntime
// （x86_64 25.6 MB / arm64-v8a 22.2 MB / armeabi-v7a 15.4 MB）。flutter 的
// `--target-platform` 只管 libflutter / libapp，插件自带的 jniLibs 仍会全部
// 打进包体，于是三条 ABI 全带走能到 ~180 MB。
//
// 这里读 flutter 传下来的 `-Ptarget-platform`，换算成 ABI 白名单再交给
// ndk.abiFilters，多出来的 ABI 就不会进包：
//   flutter build apk --release                     → arm64-v8a（商店分发包，约 72 MB）
//   flutter build apk --release --target-platform android-x64 → x86_64（模拟器验证包）
// 不指定平台时 flutter 会把三条 ABI 一起传下来，此时按「真机分发」收窄到 arm64；
// 只要显式指定了单一平台，就尊重用户的选择。
// ---------------------------------------------------------------------------
val requestedPlatforms: List<String> = (project.findProperty("target-platform") as String?)
    ?.split(",")
    ?.map { it.trim() }
    ?.filter { it.isNotEmpty() }
    .orEmpty()

val explicitSinglePlatform = requestedPlatforms.size == 1

// flutter 传下来的 `-Psplit-per-abi=true`：AGP 会按 ABI 拆成多个 APK。
val splitPerAbi: Boolean = (project.findProperty("split-per-abi") as String?)
    ?.toBoolean() ?: false

val releaseAbis: List<String> = run {
    val archToAbi = mapOf(
        "android-arm" to "armeabi-v7a",
        "android-arm64" to "arm64-v8a",
        "android-x64" to "x86_64",
    )
    val requested = requestedPlatforms.mapNotNull { archToAbi[it] }.distinct()
    when {
        requested.isEmpty() -> listOf("arm64-v8a")
        requested.size == 1 -> requested
        else -> listOf("arm64-v8a") // 多平台 = 默认全量构建，发布只留 arm64
    }
}

android {
    namespace = "com.example.operit_flutter_project"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.operit.sakuraread"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // 内置小模型依赖的 mediapipe / protobuf 有「编译期注解类缺失」与 JNI 反射
            // 两个坑，R8 需要这份规则才不会把 release 包打挂（详见 proguard-rules.pro）。
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        debug {
            // 调试包给模拟器 / 真机现场调试用，不限制 ABI，免得换台设备就跑不起来。
        }
    }

    // 再省一截下载体积：AGP 默认把 .so 以「不压缩」方式放进 APK（装得快），
    // 但这几个库本来就大（onnxruntime 22 MB），不压缩会让安装包白白多出十几 MB。
    // 这里改成传统打包（压缩存储），安装时由系统解压 —— 磁盘占用不变，下载体积明显变小。
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

// 发布包的 ABI 白名单：abiFilters 会被 Flutter 插件在 apply 时覆盖掉，AGP 还会把
// defaultConfig 与 buildType 的过滤条件取并集，所以这里改在「打包阶段」按变体剔除
// 多余的架构目录 —— 这是真正决定 APK 里有哪些 .so 的一层。
androidComponents {
    onVariants { variant ->
        // `--split-per-abi` 时 AGP 自己会按 ABI 拆包，这时再做 excludes 会把每条
        // 分片里的 .so 全剔掉（试过：x86_64 / v7a 分片只剩 25 MB、里面一个 lib 都没有）。
        if (splitPerAbi) return@onVariants
        // release 永远只留 releaseAbis；debug 只在用户显式指定了单一平台时收窄，
        // 免得 `flutter run` 换台模拟器就跑不起来。
        val abis = when {
            variant.buildType == "release" -> releaseAbis
            explicitSinglePlatform -> releaseAbis
            else -> emptyList()
        }
        if (abis.isEmpty() || abis.size >= 3) return@onVariants
        val all = listOf("armeabi-v7a", "arm64-v8a", "x86_64")
        val excluded = all.filterNot { abis.contains(it) }
        variant.packaging.jniLibs.excludes.addAll(excluded.map { "lib/$it/**" })
    }
}

// 再省一截下载体积：AGP 默认把 .so 以「不压缩」方式放进 APK（装得快），
// 但这几个库本来就大（onnxruntime 22 MB），不压缩会让安装包白白多出十几 MB。
// 上面 buildTypes 里的 packaging.jniLibs.useLegacyPackaging = true 就是干这个的。

flutter {
    source = "../.."
}

// ---------------------------------------------------------------------------
// 内置本地小模型（离线 AI 助手）
//
// MediaPipe LLM Inference（Apache-2.0）提供 .task 格式模型的端侧推理：
// 一个 521 MB 的 Qwen2.5-0.5B 就能在手机上跑出可用的小助手，不需要联网、
// 不需要 API Key。AAR 自带每条 ABI 的 libllm_inference_engine_jni.so
// （arm64-v8a 11.9 MB / x86_64 13.5 MB），上面的 abiFilters 会保证只有目标
// ABI 的那一份被打进包，不会三份全带。
//
// 引擎与模型解耦：想换 1.5B / 3B 只需要在 Dart 侧 localModelCatalog 里加一条。
// ---------------------------------------------------------------------------
dependencies {
    implementation("com.google.mediapipe:tasks-genai:0.10.24")
}
