package com.example.operit_flutter_project

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * 内置「本地小模型」推理通道（MediaPipe LLM Inference，Apache-2.0）。
 *
 * 模型是 .task 包（Qwen2.5-Instruct 的 LiteRT/MediaPipe 版本），由 Dart 侧下载到
 * 应用私有目录，这里只负责：加载模型 / 流式吐字 / 取消 / 卸载。
 *
 * 之所以自己写一层 MethodChannel 而不是引第三方插件：可以精确控制模型路径、
 * 流式回调与内存释放，也不会带进一堆用不上的依赖（APK 体积敏感）。
 */
class LocalLlmEngine(context: Context, messenger: BinaryMessenger) {

    companion object {
        const val CHANNEL = "sakuramanga/llm"

        /** 原生 → Dart 的流式事件方法名。 */
        const val EVENT = "llm.event"
    }

    private val appContext: Context = context.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()

    private var engine: LlmInference? = null
    private var loadedPath: String? = null
    private var loadedMaxTokens: Int = 0
    private var generating = false
    private var cancelled = false
    private var generationId = 0

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "info" -> result.success(info())
                "load" -> load(
                    call.argument<String>("path"),
                    call.argument<Int>("maxTokens") ?: 1280,
                    result,
                )
                "generate" -> generate(
                    call.argument<String>("prompt") ?: "",
                    result,
                )
                "cancel" -> {
                    cancelled = true
                    result.success(null)
                }
                "unload" -> unload(result)
                "tokenCount" -> tokenCount(call.argument<String>("text") ?: "", result)
                else -> result.notImplemented()
            }
        }
    }

    /** 设备 / 引擎现状，Dart 用它决定要不要显示「本地模型」入口。 */
    private fun info(): Map<String, Any?> {
        var totalMemMb = 0L
        try {
            val am = appContext.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val mi = ActivityManager.MemoryInfo()
            am.getMemoryInfo(mi)
            totalMemMb = mi.totalMem / (1024L * 1024L)
        } catch (_: Throwable) {
        }
        return mapOf(
            "supported" to true,
            "loaded" to (engine != null),
            "path" to loadedPath,
            "maxTokens" to loadedMaxTokens,
            "totalMemMb" to totalMemMb,
            "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: ""),
        )
    }

    private fun load(path: String?, maxTokens: Int, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("bad_path", "模型路径为空", null)
            return
        }
        val file = File(path)
        if (!file.isFile || file.length() <= 0L) {
            result.error("missing_model", "模型文件不存在：$path", null)
            return
        }
        val size = file.length()
        worker.execute {
            try {
                closeEngine()
                val options = LlmInference.LlmInferenceOptions.builder()
                    .setModelPath(path)
                    .setMaxTokens(maxTokens)
                    // 贪心解码偏保守，避免小模型跑飞；温度相关参数由 prompts 控制。
                    .setMaxTopK(40)
                    .build()
                val created = LlmInference.createFromOptions(appContext, options)
                engine = created
                loadedPath = path
                loadedMaxTokens = maxTokens
                main.post {
                    result.success(
                        mapOf(
                            "loaded" to true,
                            "path" to path,
                            "bytes" to size,
                            "maxTokens" to maxTokens,
                        ),
                    )
                }
            } catch (t: Throwable) {
                closeEngine()
                val message = t.message ?: t.javaClass.simpleName
                main.post {
                    result.error(
                        "load_failed",
                        "模型加载失败（可能是内存不足或文件损坏）：$message",
                        null,
                    )
                }
            }
        }
    }

    /**
     * 流式生成。返回前先把 result.success 回了（只表示「已开始」），
     * 真正的文本通过 [EVENT] 事件逐段推给 Dart：
     *   { id, type: partial|done|error, text }
     */
    private fun generate(prompt: String, result: MethodChannel.Result) {
        val current = engine
        if (current == null) {
            result.error("not_loaded", "本地模型还没加载好", null)
            return
        }
        if (prompt.isBlank()) {
            result.error("empty_prompt", "提示词为空", null)
            return
        }
        if (generating) {
            result.error("busy", "上一条还在生成，稍等一下", null)
            return
        }
        generating = true
        cancelled = false
        generationId += 1
        val id = generationId
        result.success(mapOf("id" to id))

        try {
            current.generateResponseAsync(prompt) { partial, done ->
                if (cancelled) {
                    if (done) {
                        generating = false
                        emit(id, "done", "")
                    }
                    return@generateResponseAsync
                }
                if (done) {
                    generating = false
                    emit(id, "done", "")
                } else if (!partial.isNullOrEmpty()) {
                    emit(id, "partial", partial)
                }
            }
        } catch (t: Throwable) {
            generating = false
            emit(id, "error", t.message ?: t.javaClass.simpleName)
        }
    }

    private fun emit(id: Int, type: String, text: String) {
        main.post {
            try {
                channel.invokeMethod(
                    EVENT,
                    mapOf("id" to id, "type" to type, "text" to text),
                )
            } catch (_: Throwable) {
                // Dart 侧还没挂上 handler（早期调用）时忽略即可。
            }
        }
    }

    private fun tokenCount(text: String, result: MethodChannel.Result) {
        val current = engine
        if (current == null) {
            // 没加载时给个粗略估算（中文约 1 字 1 token，英文约 4 字符 1 token）。
            var cjk = 0
            var other = 0
            for (ch in text) {
                if (ch.code in 0x2E80..0x9FFF || ch.code in 0xFF00..0xFFEF) cjk++ else other++
            }
            result.success(cjk + other / 4 + 1)
            return
        }
        try {
            result.success(current.sizeInTokens(text))
        } catch (_: Throwable) {
            result.success(text.length)
        }
    }

    private fun unload(result: MethodChannel.Result) {
        worker.execute {
            closeEngine()
            main.post { result.success(true) }
        }
    }

    private fun closeEngine() {
        try {
            engine?.close()
        } catch (_: Throwable) {
        }
        engine = null
        loadedPath = null
        loadedMaxTokens = 0
        generating = false
    }

    /** Activity 销毁时释放 native 内存（模型常驻时占用几百 MB）。 */
    fun dispose() {
        cancelled = true
        worker.execute { closeEngine() }
        worker.shutdown()
    }
}
