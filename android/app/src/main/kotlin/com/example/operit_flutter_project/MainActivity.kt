package com.example.operit_flutter_project

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.view.KeyEvent
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val channelName = "sakuramanga/native"

    /// 独立通道：文件打开事件（与 native 通道分开，避免覆盖 TTS 的事件处理器）。
    private val openChannelName = "sakuramanga/open"

    /// 独立通道：音量键翻页事件（原生 → Dart）。
    private val keysChannelName = "sakuramanga/keys"

    // ---- 朗读（TTS）状态 ----
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var ttsInitRequested = false

    /** 当前生效的引擎包名（null = 系统默认）；用于判断是否需要重建实例。 */
    private var currentEngine: String? = null
    private var ttsChannel: MethodChannel? = null
    private var openChannel: MethodChannel? = null

    /** 内置本地小模型（离线 AI 助手）推理通道。 */
    private var localLlm: LocalLlmEngine? = null

    // ---- 文件打开（VIEW intent）状态 ----
    // 冷启动时系统把文件 intent 传进来，Dart 尚未就绪 → 先存路径等 Dart 来取；
    // 热启动（已有实例）时通过 [notifyFileOpened] 直接推送。
    private var pendingOpenPath: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingOpenPath = resolveOpenIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // 热启动：App 已在运行，用户又用「打开方式」选了一个文件 → 直接推送
        val path = resolveOpenIntent(intent)
        if (path != null) {
            pendingOpenPath = path
            notifyFileOpened(path)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ttsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        // 内置本地小模型（离线 AI）通道，与 TTS 一样挂在这个 Activity 上
        localLlm = LocalLlmEngine(this, flutterEngine.dartExecutor.binaryMessenger)
        // 音量键事件通道：原生 onKeyDown 通过它把翻页动作送回 Dart
        keyChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, keysChannelName)
        // 文件打开通道：独立于 native 通道（两处都要 setMethodCallHandler，
        // 同一通道会互相覆盖）
        openChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, openChannelName)
        openChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                // Dart 就绪后调用：取走启动时收到的文件路径（取后清除）
                "getLaunchFile" -> {
                    val p = pendingOpenPath
                    pendingOpenPath = null
                    result.success(p)
                }
                else -> result.notImplemented()
            }
        }
        ttsChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasStoragePermission" -> result.success(hasStoragePermission())
                "requestStoragePermission" -> {
                    requestStoragePermission()
                    result.success(null)
                }
                "setKeepScreenOn" -> {
                    val on = call.arguments as? Boolean ?: false
                    if (on) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                "getStorageRoot" -> {
                    val root = Environment.getExternalStorageDirectory()
                    result.success(root?.absolutePath ?: "/storage/emulated/0")
                }
                "getDirs" -> {
                    val map = HashMap<String, String>()
                    map["files"] = filesDir.absolutePath
                    map["cache"] = cacheDir.absolutePath
                    result.success(map)
                }
                "getBattery" -> {
                    val intent = registerReceiver(
                        null as android.content.BroadcastReceiver?,
                        android.content.IntentFilter(android.content.Intent.ACTION_BATTERY_CHANGED),
                    )
                    var level = -1
                    var charging = false
                    if (intent != null) {
                        val l = intent.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1)
                        val s = intent.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, -1)
                        if (l >= 0 && s > 0) level = l * 100 / s
                        val st = intent.getIntExtra(android.os.BatteryManager.EXTRA_STATUS, -1)
                        charging = st == android.os.BatteryManager.BATTERY_STATUS_CHARGING ||
                            st == android.os.BatteryManager.BATTERY_STATUS_FULL
                    }
                    val map = HashMap<String, Any>()
                    map["level"] = level
                    map["charging"] = charging
                    result.success(map)
                }
                // ---------- 打开链接（设置页「项目主页」等） ----------
                "openUrl" -> {
                    val url = call.arguments as? String ?: ""
                    result.success(openUrl(url))
                }
                // ---------- 应用内更新（安装新版本 APK） ----------
                "installApk" -> {
                    val path = call.arguments as? String ?: ""
                    result.success(installApk(path))
                }
                "canInstallApk" -> result.success(canInstallApk())
                "openInstallPermission" -> {
                    openInstallPermission()
                    result.success(null)
                }
                // ---------- 朗读（TTS） ----------
                "ttsEngines" -> result.success(listTtsEngines())
                // 跳转系统语音合成设置：用户机器上没有中文语音引擎时，
                // 把他直接送到能安装 / 选择引擎的地方（用户反馈）。
                "openTtsSettings" -> result.success(openTtsSettings())
                "ttsInit" -> {
                    val engine = call.argument<String>("engine")
                    initTts(engine, result)
                }
                "ttsSpeak" -> {
                    val text = call.argument<String>("text") ?: ""
                    val utteranceId = call.argument<String>("utteranceId") ?: "u"
                    val queue = call.argument<Boolean>("flush") ?: true
                    speak(text, utteranceId, queue)
                    result.success(ttsReady)
                }
                "ttsStop" -> {
                    tts?.stop()
                    stopOfflinePlayer()
                    result.success(null)
                }
                "ttsSetRate" -> {
                    val rate = call.argument<Double>("rate") ?: 1.0
                    tts?.setSpeechRate(rate.toFloat())
                    result.success(null)
                }
                "ttsSetPitch" -> {
                    val pitch = call.argument<Double>("pitch") ?: 1.0
                    tts?.setPitch(pitch.toFloat())
                    result.success(null)
                }
                "ttsIsSpeaking" -> result.success(tts?.isSpeaking == true)
                "ttsShutdown" -> {
                    shutdownTts()
                    result.success(null)
                }
                // ---------- 内置离线语音（Dart 侧合成，这里只负责播放） ----------
                // 用户反馈：很多机型没有系统语音引擎 → App 自带一套离线合成，
                // Dart 合成出 WAV 后交给这里播放（复用同一套 ttsState 事件）。
                "ttsPlayFile" -> {
                    val path = call.argument<String>("path") ?: ""
                    val utteranceId = call.argument<String>("utteranceId") ?: "u"
                    result.success(playAudioFile(path, utteranceId))
                }
                // ---------- 音量键翻页 ----------
                // Dart 进入/退出阅读页时开关；开启后 onKeyDown 拦截音量键。
                "setVolumeKeyPaging" -> {
                    volumeKeyPaging = call.arguments as? Boolean ?: false
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ==================== 音量键翻页 ====================

    /**
     * 音量键翻页开关：只有在阅读页且用户打开了这个开关时才接管音量键。
     *
     * 用户反馈「音量键翻页」是很多阅读器用户的习惯操作。默认关闭，
     * 打开后音量键不再调音量，而是交给阅读器翻页。
     */
    private var volumeKeyPaging = false

    /** 音量键事件通道（原生 → Dart 主动 invoke）。 */
    private var keyChannel: MethodChannel? = null

    /**
     * 拦截音量键：音量下 = 下一页，音量上 = 上一页。
     *
     * 只有 Dart 侧明确开启（阅读页 + 用户开了开关）才吞掉事件，
     * 其它场景照常交给系统调音量，不会影响用户日常使用。
     */
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (volumeKeyPaging) {
            when (keyCode) {
                KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    keyChannel?.invokeMethod("volumeKeyPage", "next")
                    return true
                }
                KeyEvent.KEYCODE_VOLUME_UP -> {
                    keyChannel?.invokeMethod("volumeKeyPage", "prev")
                    return true
                }
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    // ==================== 朗读（TTS）实现 ====================

    /**
     * 打开系统「语音合成 / TTS 输出」设置页。
     *
     * 用户反馈：手机没装语音引擎时只看到一句「朗读暂时不可用」，
     * 完全不知道去哪解决。这里按优先级尝试多个系统入口，
     * 都拉不起来就退到本应用的详情页（用户可自行进系统设置）。
     */
    private fun openTtsSettings(): Boolean {        val candidates = listOf(
            Intent("com.android.settings.TTS_SETTINGS"),
            Intent(android.provider.Settings.ACTION_SETTINGS).apply {
                putExtra(":settings:show_fragment", "com.android.settings.TtsSettings")
            },
            Intent("com.android.settings.TTS_SETTINGS"),
        )
        for (intent in candidates) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return true
            } catch (_: Exception) {
                // 换下一个入口
            }
        }
        // 兜底：本应用详情页（里面有「默认设置」等系统入口）
        return try {
            val intent = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = android.net.Uri.fromParts("package", packageName, null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    /** 列出系统可用的 TTS 引擎包名。 */
    private fun listTtsEngines(): List<String> {
        return try {
            val intent = Intent(TextToSpeech.Engine.INTENT_ACTION_TTS_SERVICE)
            val services = packageManager.queryIntentServices(intent, PackageManager.MATCH_DEFAULT_ONLY)
            services.mapNotNull { it.serviceInfo?.packageName }.distinct()
        } catch (_: Exception) {
            emptyList()
        }
    }

    /**
     * 初始化 TTS。
     *  - engine 为 null / 空：交给系统选默认引擎；
     *  - 中文失败时自动回退到 Locale.CHINA / CHINESE；
     *  - 通过 [MethodChannel] 回传 ttsState 事件（ready / start / done / error）。
     *
     * 用户反馈「一加15 自带语音引擎，用不了朗读」的应对：
     *  - 允许 Dart 侧**逐个引擎重试**（每次调用都重建实例，不再被
     *    [ttsInitRequested] 永久挡死）；
     *  - 构造 / 初始化失败时**释放旧实例**再返回失败，避免半死实例占着。
     */
    private fun initTts(engine: String?, result: MethodChannel.Result) {
        // 已经就绪且引擎没变：直接复用
        if (ttsReady && tts != null && engine == currentEngine) {
            result.success(true)
            return
        }
        // 换引擎 / 上次失败：先释放旧实例，重新建
        releaseTts()
        ttsInitRequested = true
        try {
            val listener = TextToSpeech.OnInitListener { status ->
                if (status == TextToSpeech.SUCCESS) {
                    val engineObj = tts
                    if (engineObj != null) {
                        applyChineseLocale(engineObj)
                        engineObj.setOnUtteranceProgressListener(progressListener)
                        ttsReady = true
                        currentEngine = engine
                    }
                } else {
                    ttsReady = false
                }
                notifyTts(if (ttsReady) "ready" else "error")
                runOnUiThread { result.success(ttsReady) }
            }
            tts = if (!engine.isNullOrEmpty()) {
                TextToSpeech(this, listener, engine)
            } else {
                TextToSpeech(this, listener)
            }
        } catch (e: Exception) {
            ttsReady = false
            ttsInitRequested = false
            releaseTts()
            notifyTts("error")
            result.success(false)
        }
    }

    /** 释放当前 TTS 实例（换引擎 / 重试前调用）。 */
    private fun releaseTts() {
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {
        }
        tts = null
        ttsReady = false
        ttsInitRequested = false
        currentEngine = null
    }

    /** 设置中文（优先 zh-CN，退而求其次 zh）。 */
    private fun applyChineseLocale(engine: TextToSpeech) {
        try {
            val r = engine.setLanguage(Locale.CHINA)
            if (r == TextToSpeech.LANG_MISSING_DATA || r == TextToSpeech.LANG_NOT_SUPPORTED) {
                engine.setLanguage(Locale.CHINESE)
            }
        } catch (_: Exception) {
        }
    }

    private val progressListener = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String?) {
            notifyTts("start", utteranceId)
        }

        override fun onDone(utteranceId: String?) {
            notifyTts("done", utteranceId)
        }

        @Deprecated("Deprecated in Java")
        override fun onError(utteranceId: String?) {
            notifyTts("error", utteranceId)
        }

        override fun onError(utteranceId: String?, errorCode: Int) {
            notifyTts("error", utteranceId)
        }
    }

    private fun notifyTts(state: String, utteranceId: String? = null) {
        runOnUiThread {
            try {
                ttsChannel?.invokeMethod(
                    "ttsState",
                    hashMapOf("state" to state, "utteranceId" to (utteranceId ?: "")),
                )
            } catch (_: Exception) {
            }
        }
    }

    private fun speak(text: String, utteranceId: String, flush: Boolean) {
        val engine = tts ?: return
        if (text.isEmpty()) return
        try {
            val mode = if (flush) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD
            engine.speak(text, mode, null, utteranceId)
        } catch (_: Exception) {
        }
    }

    // ==================== 内置离线语音播放 ====================

    /** 播放离线合成出来的 WAV 文件（Dart 侧用 sherpa-onnx 合成）。 */
    private var offlinePlayer: android.media.MediaPlayer? = null

    /**
     * 播放一段合成好的音频，并像系统 TTS 一样回传 start / done / error 事件。
     *
     * 为什么用 MediaPlayer 而不是 Dart 侧的音频库：项目本来就有原生通道，
     * 复用它能少一个依赖，而且文件播放没有延迟、也不用申请音频焦点权限。
     */
    private fun playAudioFile(path: String, utteranceId: String): Boolean {
        if (path.isEmpty()) return false
        val file = java.io.File(path)
        if (!file.exists() || file.length() == 0L) return false
        stopOfflinePlayer()
        return try {
            val player = android.media.MediaPlayer()
            player.setDataSource(path)
            player.setOnCompletionListener {
                notifyTts("done", utteranceId)
                stopOfflinePlayer()
            }
            player.setOnErrorListener { _, _, _ ->
                notifyTts("error", utteranceId)
                stopOfflinePlayer()
                true
            }
            player.prepare()
            player.start()
            offlinePlayer = player
            notifyTts("start", utteranceId)
            true
        } catch (e: Exception) {
            notifyTts("error", utteranceId)
            stopOfflinePlayer()
            false
        }
    }

    /** 停止内置语音播放（暂停 / 停止朗读时调用）。 */
    private fun stopOfflinePlayer() {
        val player = offlinePlayer
        offlinePlayer = null
        if (player == null) return
        try {
            if (player.isPlaying) player.stop()
        } catch (_: Exception) {
        }
        try {
            player.release()
        } catch (_: Exception) {
        }
    }

    private fun shutdownTts() {
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {
        }
        tts = null
        ttsReady = false
        ttsInitRequested = false
        currentEngine = null
        stopOfflinePlayer()
    }

    /** 用系统浏览器打开链接（失败时返回 false，由 Dart 侧提示）。 */
    private fun openUrl(url: String): Boolean {
        if (url.isEmpty()) return false
        return try {
            startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK,
                ),
            )
            true
        } catch (_: Exception) {
            false
        }
    }

    // ==================== 应用内更新（安装 APK）实现 ====================

    /**
     * 调起系统安装器安装指定路径的 APK。
     *
     * 为什么必须走 FileProvider：Android 7.0 起用 `file://` 分享安装包会抛
     * `FileUriExposedException`；新版系统把「安装未知应用」收进各自的授权页，
     * 这里统一用 `content://` + 临时读权限交给安装器。
     */
    private fun installApk(path: String): Boolean {
        if (path.isEmpty()) return false
        val file = java.io.File(path)
        if (!file.exists() || file.length() <= 0L) {
            android.util.Log.w("SakuraRead", "installApk: file missing or empty")
            return false
        }
        return try {
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            android.util.Log.w("SakuraRead", "installApk failed", e)
            false
        }
    }

    /** 是否已允许「从本应用安装未知来源应用」（Android 8.0+ 需单独授权）。 */
    private fun canInstallApk(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    /** 跳转系统设置页，让用户授权「安装未知来源应用」。 */
    private fun openInstallPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                ),
            )
        } catch (_: Exception) {
        }
    }

    // ==================== 文件打开（VIEW intent）实现 ====================

    /**
     * 解析「用樱读打开」的文件 intent，返回可读路径（无则 null）。
     *
     * 支持两种来源：
     *  - `file://`（文件管理器直接传路径）：直接用该路径；
     *  - `content://`（系统 DocumentsUI / 第三方应用共享）：把内容复制到
     *    App 缓存目录下的固定文件，返回缓存路径（缓存目录无需权限即可读）。
     */
    private fun resolveOpenIntent(intent: Intent?): String? {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return null
        val data = intent.data ?: return null
        return try {
            val path = when (data.scheme) {
                "file" -> data.path
                "content" -> copyContentToCache(data)
                else -> null
            }
            if (!path.isNullOrEmpty()) {
                android.util.Log.i("SakuraRead", "open file: $path")
                path
            } else {
                null
            }
        } catch (e: Exception) {
            android.util.Log.w("SakuraRead", "open file failed", e)
            null
        }
    }

    /** 把 content:// 指向的文件复制到缓存目录，返回缓存文件路径。 */
    private fun copyContentToCache(uri: Uri): String? {
        val name = queryDisplayName(uri) ?: "opened_file"
        // 用固定前缀 + 原名：若同名文件已存在则先删除，保证是本次内容
        val safe = name.replace(Regex("[\\\\/:*?\"<>|]"), "_")
        val target = java.io.File(cacheDir, "open/$safe")
        target.parentFile?.mkdirs()
        if (target.exists()) target.delete()
        contentResolver.openInputStream(uri)?.use { input ->
            target.outputStream().use { output ->
                input.copyTo(output)
            }
        } ?: return null
        return target.absolutePath
    }

    /** 读取 content:// 的显示名（用于给缓存文件起原名）。 */
    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val idx = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                if (idx >= 0 && cursor.moveToFirst()) cursor.getString(idx) else null
            }
        } catch (_: Exception) {
            null
        }
    }

    /** 把「用户刚打开的文件」推送给 Dart 侧（热启动路径）。 */
    private fun notifyFileOpened(path: String) {
        runOnUiThread {
            try {
                openChannel?.invokeMethod("fileOpened", path)
            } catch (_: Exception) {
            }
        }
    }

    override fun onDestroy() {
        // 本地模型占着几百 MB native 内存，Activity 退出时务必释放
        localLlm?.dispose()
        localLlm = null
        shutdownTts()
        super.onDestroy()
    }

    private fun hasStoragePermission(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            return Environment.isExternalStorageManager()
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return checkSelfPermission(android.Manifest.permission.READ_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }
        return true
    }

    private fun requestStoragePermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val intent = Intent(
                    Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                    Uri.parse("package:$packageName"),
                )
                startActivity(intent)
            } catch (e: Exception) {
                try {
                    startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                } catch (_: Exception) {
                }
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            requestPermissions(
                arrayOf(
                    android.Manifest.permission.READ_EXTERNAL_STORAGE,
                    android.Manifest.permission.WRITE_EXTERNAL_STORAGE,
                ),
                1001,
            )
        }
    }
}
