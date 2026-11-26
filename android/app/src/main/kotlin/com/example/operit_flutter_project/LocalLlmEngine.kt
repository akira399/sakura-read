package com.example.operit_flutter_project

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.Message
import com.google.ai.edge.litertlm.MessageCallback
import com.google.ai.edge.litertlm.SamplerConfig
import com.google.ai.edge.litertlm.ThinkingConfig
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 内置「本地小模型」推理通道（Google LiteRT-LM，Apache-2.0）。
 *
 * 模型是 .litertlm 包（Qwen3 / Qwen3.5 / LFM2.5 / Gemma 4 等端侧模型），
 * 由 Dart 侧下载到应用私有目录，这里负责：加载引擎 / 会话流式生成 / 取消 / 卸载。
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

    @Volatile
    private var workerCreated = false
    private val worker by lazy {
        workerCreated = true
        Executors.newSingleThreadExecutor()
    }

    @Volatile
    private var engine: Engine? = null

    @Volatile
    private var activeConversation: Conversation? = null

    private var loadedPath: String? = null
    private var loadedMaxTokens: Int = 0

    @Volatile
    private var generating = false

    @Volatile
    private var cancelled = false

    private var generationId = 0

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "info" -> result.success(info())
                "load" -> load(
                    call.argument<String>("path"),
                    call.argument<Int>("maxTokens") ?: 2048,
                    result,
                )
                "generate" -> {
                    val rawHistory = call.argument<List<Map<String, Any?>>>("history")
                    generate(
                        prompt = call.argument<String>("prompt") ?: "",
                        system = call.argument<String>("system"),
                        history = rawHistory,
                        enableThinking = call.argument<Boolean>("enableThinking") ?: false,
                        result = result,
                    )
                }
                "cancel" -> {
                    cancelled = true
                    try {
                        activeConversation?.cancelProcess()
                    } catch (_: Throwable) {
                    }
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
                val config = EngineConfig(
                    modelPath = path,
                    backend = Backend.CPU(),
                    maxNumTokens = maxTokens,
                    cacheDir = appContext.cacheDir.path,
                )
                val created = Engine(config).apply { initialize() }
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
    private fun generate(
        prompt: String,
        system: String?,
        history: List<Map<String, Any?>>?,
        enableThinking: Boolean,
        result: MethodChannel.Result,
    ) {
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

        worker.execute {
            try {
                val initialMessages = buildList {
                    history?.forEach { turn ->
                        val content = turn["content"]?.toString()?.trim().orEmpty()
                        if (content.isNotEmpty()) {
                            val role = turn["role"]?.toString()
                            add(
                                if (role == "assistant") {
                                    Message.model(content)
                                } else {
                                    Message.user(content)
                                },
                            )
                        }
                    }
                }
                val convConfig = ConversationConfig(
                    systemInstruction = system?.takeIf { it.isNotBlank() }?.let { Contents.of(it) },
                    initialMessages = initialMessages,
                    samplerConfig = SamplerConfig(
                        topK = 40,
                        topP = 0.9,
                        temperature = 0.6,
                    ),
                    maxOutputToken = 512,
                    thinkingConfig = ThinkingConfig(enableThinking = enableThinking),
                )
                val conversation = current.createConversation(convConfig)
                activeConversation = conversation
                val finished = AtomicBoolean(false)

                fun releaseConversation() {
                    if (activeConversation === conversation) {
                        activeConversation = null
                    }
                    generating = false
                    worker.execute {
                        try {
                            conversation.close()
                        } catch (_: Throwable) {
                        }
                    }
                }

                conversation.sendMessageAsync(
                    prompt,
                    object : MessageCallback {
                        override fun onMessage(message: Message) {
                            if (cancelled || finished.get()) return
                            val text = message.contents.contents
                                .filterIsInstance<Content.Text>()
                                .joinToString("") { it.text }
                            if (text.isNotEmpty()) {
                                emit(id, "partial", text)
                            }
                        }

                        override fun onDone() {
                            if (!finished.compareAndSet(false, true)) return
                            releaseConversation()
                            emit(id, "done", "")
                        }

                        override fun onError(throwable: Throwable) {
                            if (!finished.compareAndSet(false, true)) return
                            releaseConversation()
                            if (cancelled) {
                                emit(id, "done", "")
                            } else {
                                emit(id, "error", throwable.message ?: throwable.javaClass.simpleName)
                            }
                        }
                    },
                )
            } catch (t: Throwable) {
                activeConversation = null
                generating = false
                if (cancelled) {
                    emit(id, "done", "")
                } else {
                    emit(id, "error", t.message ?: t.javaClass.simpleName)
                }
            }
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
        // 中文约 1 字 1 token，英文约 4 字符 1 token，用于预算裁切足够准确且零阻塞。
        var cjk = 0
        var other = 0
        for (ch in text) {
            if (ch.code in 0x2E80..0x9FFF || ch.code in 0xFF00..0xFFEF) cjk++ else other++
        }
        result.success(cjk + other / 4 + 1)
    }

    private fun unload(result: MethodChannel.Result) {
        cancelled = true
        worker.execute {
            closeEngine()
            main.post { result.success(true) }
        }
    }

    private fun closeEngine() {
        try {
            activeConversation?.cancelProcess()
        } catch (_: Throwable) {
        }
        try {
            activeConversation?.close()
        } catch (_: Throwable) {
        }
        activeConversation = null
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
        if (!workerCreated) return
        worker.execute { closeEngine() }
        worker.shutdown()
    }
}
