package com.example.operit_flutter_project

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
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

    // ---- 朗读（TTS）状态 ----
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var ttsInitRequested = false
    private var ttsChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ttsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
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
