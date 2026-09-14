package io.instance001.chatty_venture

import androidx.annotation.Keep

@Keep
class NativeLlamaBridge {
    private var callback: NativeGenerationCallback? = null
    fun loadModel(modelPath: String, contextSize: Int): Boolean = libraryLoaded && nativeLoadModel(modelPath, contextSize, 0)
    fun lastError(): String = if (libraryLoaded) nativeGetLastError() else "Native llama.cpp library is unavailable."
    fun cancel() { if (libraryLoaded) nativeRequestCancel() }
    fun unload() { if (libraryLoaded) nativeUnloadModel() }
    fun generate(requestId: String, modelPath: String, prompt: String, contextSize: Int, maxTokens: Int, callback: NativeGenerationCallback): Boolean {
        if (!libraryLoaded) return false
        this.callback = callback
        return nativeStartGeneration(requestId, modelPath, prompt, contextSize, maxTokens, 0.48, 0.86, 40, 0)
    }
    fun onNativeToken(requestId: String, text: String) { callback?.onToken(requestId, text) }
    fun onNativeCompleted(requestId: String, text: String) { callback?.onCompleted(requestId, text) }
    fun onNativeFailed(requestId: String, message: String) { callback?.onFailed(requestId, message) }
    fun onNativeCancelled(requestId: String) { callback?.onCancelled(requestId) }
    external fun nativeLoadModel(modelPath: String, contextSize: Int, gpuLayers: Int): Boolean
    external fun nativeGetLastError(): String
    external fun nativeStartGeneration(requestId: String, modelPath: String, prompt: String, contextSize: Int, maxTokens: Int, temperature: Double, topP: Double, topK: Int, gpuLayers: Int): Boolean
    external fun nativeRequestCancel()
    external fun nativeUnloadModel()
    companion object { private val libraryLoaded = try { System.loadLibrary("chatty_llama"); true } catch (_: UnsatisfiedLinkError) { false } }
}

interface NativeGenerationCallback {
    fun onToken(requestId: String, text: String)
    fun onCompleted(requestId: String, text: String)
    fun onFailed(requestId: String, message: String)
    fun onCancelled(requestId: String)
}
