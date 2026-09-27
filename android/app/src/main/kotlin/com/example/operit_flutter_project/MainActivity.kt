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
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val channelName = "sakuramanga/native"

    /// 独立通道：文件打开事件（与 native 通道分开，避免覆盖 TTS 的事件处理器）。
    private val openChannelName = "sakuramanga/open"

    // ---- 朗读（TTS）状态 ----
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var ttsInitRequested = false
    private var ttsChannel: MethodChannel? = null
    private var openChannel: MethodChannel? = null

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
                // ---------- 朗读（TTS） ----------
                "ttsEngines" -> result.success(listTtsEngines())
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
                else -> result.notImplemented()
            }
        }
    }

    // ==================== 朗读（TTS）实现 ====================

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
     */
    private fun initTts(engine: String?, result: MethodChannel.Result) {
        if (ttsReady && tts != null) {
            result.success(true)
            return
        }
        if (ttsInitRequested) {
            result.success(false)
            return
        }
        ttsInitRequested = true
        try {
            val listener = TextToSpeech.OnInitListener { status ->
                if (status == TextToSpeech.SUCCESS) {
                    val engineObj = tts
                    if (engineObj != null) {
                        applyChineseLocale(engineObj)
                        engineObj.setOnUtteranceProgressListener(progressListener)
                        ttsReady = true
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
            notifyTts("error")
            result.success(false)
        }
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

    private fun shutdownTts() {
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {
        }
        tts = null
        ttsReady = false
        ttsInitRequested = false
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
