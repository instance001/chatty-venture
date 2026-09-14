package io.instance001.chatty_venture

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val bridge = NativeLlamaBridge()
    private val cloudKeys by lazy { CloudKeyBridge(applicationContext) }
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chatty_venture/local_gguf").setMethodCallHandler { call, result ->
            when (call.method) {
                "generate" -> {
                    val modelPath = call.argument<String>("modelPath")
                    val prompt = call.argument<String>("prompt")
                    val contextSize = call.argument<Int>("contextSize") ?: 1536
                    val maxTokens = call.argument<Int>("maxTokens") ?: 120
                    if (modelPath.isNullOrBlank() || prompt.isNullOrBlank()) {
                        result.error("missing_generation_args", "A selected GGUF model and narrator prompt are required.", null)
                    } else {
                        startGeneration(modelPath, prompt, contextSize, maxTokens, result)
                    }
                }
                "cancel" -> { bridge.cancel(); result.success(null) }
                "unload" -> { bridge.unload(); result.success(null) }
                else -> result.notImplemented()
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "chatty_venture/local_gguf_events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { eventSink = events }
            override fun onCancel(arguments: Any?) { eventSink = null }
        })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chatty_venture/cloud_keys").setMethodCallHandler { call, result ->
            val providerId = call.argument<String>("providerId")
            if (providerId.isNullOrBlank()) { result.error("missing_provider_id", "providerId is required", null); return@setMethodCallHandler }
            try {
                when (call.method) {
                    "save" -> { val key = call.argument<String>("apiKey"); if (key.isNullOrBlank()) result.error("missing_api_key", "apiKey is required", null) else { cloudKeys.save(providerId, key); result.success(null) } }
                    "read" -> result.success(cloudKeys.read(providerId))
                    "delete" -> { cloudKeys.delete(providerId); result.success(null) }
                    "has" -> result.success(cloudKeys.has(providerId))
                    else -> result.notImplemented()
                }
            } catch (error: Exception) { result.error("cloud_key_error", error.message, null) }
        }
    }

    private fun startGeneration(modelPath: String, prompt: String, contextSize: Int, maxTokens: Int, result: MethodChannel.Result) {
        Thread {
            if (!bridge.loadModel(modelPath, contextSize)) {
                runOnUiThread { result.error("model_load_failed", bridge.lastError(), null) }
                return@Thread
            }
            val requestId = UUID.randomUUID().toString()
            val started = bridge.generate(requestId, modelPath, prompt, contextSize, maxTokens, object : NativeGenerationCallback {
                override fun onToken(requestId: String, text: String) { runOnUiThread { eventSink?.success(mapOf("type" to "token", "requestId" to requestId, "text" to text)) } }
                override fun onCompleted(requestId: String, text: String) { runOnUiThread { result.success(mapOf("text" to text)) } }
                override fun onFailed(requestId: String, message: String) { runOnUiThread { result.error("generation_failed", message, null) } }
                override fun onCancelled(requestId: String) { runOnUiThread { result.error("generation_cancelled", "Narration cancelled.", null) } }
            })
            if (!started) runOnUiThread { result.error("generation_start_failed", bridge.lastError(), null) }
        }.start()
    }
}
