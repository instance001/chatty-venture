#include <android/log.h>
#include <jni.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <codecvt>
#include <cstring>
#include <locale>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include "chat.h"
#include "common.h"
#include "llama.h"
#include "sampling.h"

namespace {

constexpr char kLogTag[] = "chatty_llama";
constexpr int kDefaultContextSize = 2048;
// Small batches and one worker keep lower-end Android CPUs responsive and
// avoid pathological long prompt-evaluation stalls on older big.LITTLE chips.
constexpr int kDefaultBatchSize = 32;
constexpr int kDefaultPredictTokens = 160;
constexpr float kDefaultTemperature = 0.7f;

std::mutex g_mutex;
std::atomic_bool g_cancel_requested = false;
bool g_backend_initialized = false;
std::string g_loaded_model_path;
int g_loaded_context_size = 0;
int g_loaded_gpu_layers = 0;
std::string g_last_error;
llama_model * g_model = nullptr;
llama_context * g_context = nullptr;
common_sampler * g_sampler = nullptr;
llama_batch g_batch = {};

struct GenerationOptions {
    int context_size = kDefaultContextSize;
    int max_tokens = kDefaultPredictTokens;
    float temperature = kDefaultTemperature;
    float top_p = 0.95f;
    int top_k = 40;
    int gpu_layers = 0;
};

bool is_valid_utf8(const char * text) {
    if (text == nullptr) {
        return true;
    }

    const auto * bytes = reinterpret_cast<const unsigned char *>(text);
    while (*bytes != 0x00) {
        int count = 0;
        if ((*bytes & 0x80) == 0x00) {
            count = 1;
        } else if ((*bytes & 0xE0) == 0xC0) {
            count = 2;
        } else if ((*bytes & 0xF0) == 0xE0) {
            count = 3;
        } else if ((*bytes & 0xF8) == 0xF0) {
            count = 4;
        } else {
            return false;
        }

        bytes += 1;
        for (int i = 1; i < count; ++i) {
            if ((*bytes & 0xC0) != 0x80) {
                return false;
            }
            bytes += 1;
        }
    }

    return true;
}

std::string finish_at_sentence_boundary(const std::string & text) {
    const size_t boundary = text.find_last_of(".!?");
    if (boundary == std::string::npos) {
        return text;
    }
    return text.substr(0, boundary + 1);
}

std::string jstring_to_utf8(JNIEnv * env, jstring value) {
    if (value == nullptr) {
        return {};
    }

    const jchar * chars = env->GetStringChars(value, nullptr);
    if (chars == nullptr) {
        return {};
    }

    const jsize length = env->GetStringLength(value);
    std::u16string utf16(reinterpret_cast<const char16_t *>(chars), static_cast<size_t>(length));
    env->ReleaseStringChars(value, chars);

    std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> converter;
    return converter.to_bytes(utf16);
}

jstring utf8_to_jstring(JNIEnv * env, const std::string & value) {
    std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> converter;
    std::u16string utf16;
    try {
        utf16 = converter.from_bytes(value);
    } catch (const std::range_error &) {
        utf16 = converter.from_bytes("(encoding error)");
    }

    return env->NewString(
        reinterpret_cast<const jchar *>(utf16.data()),
        static_cast<jsize>(utf16.size()));
}

void android_log(enum ggml_log_level level, const char * text, void * /* user_data */) {
    int priority = ANDROID_LOG_INFO;
    switch (level) {
        case GGML_LOG_LEVEL_ERROR:
            priority = ANDROID_LOG_ERROR;
            break;
        case GGML_LOG_LEVEL_WARN:
            priority = ANDROID_LOG_WARN;
            break;
        case GGML_LOG_LEVEL_DEBUG:
        case GGML_LOG_LEVEL_CONT:
            priority = ANDROID_LOG_DEBUG;
            break;
        case GGML_LOG_LEVEL_INFO:
        case GGML_LOG_LEVEL_NONE:
            priority = ANDROID_LOG_INFO;
            break;
    }
    __android_log_write(priority, kLogTag, text != nullptr ? text : "");
}

int pick_thread_count() {
    const long cpu_count = sysconf(_SC_NPROCESSORS_ONLN);
    if (cpu_count <= 2) {
      return 2;
    }
    if (cpu_count <= 4) {
      return 3;
    }
    return static_cast<int>(std::min<long>(cpu_count - 1, 4));
}

void ensure_backend_initialized() {
    if (g_backend_initialized) {
        return;
    }
    llama_log_set(android_log, nullptr);
    llama_backend_init();
    g_backend_initialized = true;
}

void unload_locked() {
    g_cancel_requested.store(false);

    if (g_sampler != nullptr) {
        common_sampler_free(g_sampler);
        g_sampler = nullptr;
    }
    if (g_context != nullptr) {
        llama_free(g_context);
        g_context = nullptr;
    }

    if (g_batch.token != nullptr) {
        llama_batch_free(g_batch);
        g_batch = {};
    }

    if (g_model != nullptr) {
        llama_model_free(g_model);
        g_model = nullptr;
    }

    g_loaded_model_path.clear();
    g_loaded_context_size = 0;
    g_loaded_gpu_layers = 0;
}

void set_last_error(const std::string & message) {
    g_last_error = message;
    __android_log_write(ANDROID_LOG_ERROR, kLogTag, g_last_error.c_str());
}

bool load_model_locked(const std::string & model_path, int context_size, int gpu_layers) {
    ensure_backend_initialized();
    g_last_error.clear();

    if (
        g_model != nullptr &&
        g_loaded_model_path == model_path &&
        g_loaded_context_size == context_size &&
        g_loaded_gpu_layers == gpu_layers &&
        g_context != nullptr
    ) {
        return true;
    }

    unload_locked();

    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = gpu_layers;
    g_model = llama_model_load_from_file(model_path.c_str(), model_params);
    if (g_model == nullptr) {
        set_last_error("llama.cpp could not load the selected GGUF model.");
        return false;
    }

    llama_context_params context_params = llama_context_default_params();
    context_params.n_ctx = context_size > 0 ? static_cast<uint32_t>(context_size) : kDefaultContextSize;
    context_params.n_batch = kDefaultBatchSize;
    context_params.n_ubatch = kDefaultBatchSize;
    context_params.n_threads = 1;
    context_params.n_threads_batch = 1;

    g_context = llama_init_from_model(g_model, context_params);
    if (g_context == nullptr) {
        set_last_error("llama.cpp failed to create a context for this model and preset.");
        unload_locked();
        return false;
    }
    __android_log_write(ANDROID_LOG_INFO, kLogTag, "context ready");

    g_batch = llama_batch_init(kDefaultBatchSize, 0, 1);
    __android_log_write(ANDROID_LOG_INFO, kLogTag, "batch ready");
    g_loaded_model_path = model_path;
    g_loaded_context_size = context_size;
    g_loaded_gpu_layers = gpu_layers;
    return true;
}

bool decode_tokens(
        const std::vector<llama_token> & tokens,
        llama_pos start_position,
        bool compute_last_logits) {
    for (size_t i = 0; i < tokens.size(); i += kDefaultBatchSize) {
        const int batch_size = static_cast<int>(std::min(tokens.size() - i, static_cast<size_t>(kDefaultBatchSize)));
        common_batch_clear(g_batch);
        for (int j = 0; j < batch_size; ++j) {
            const size_t token_index = i + j;
            const bool want_logits = compute_last_logits && token_index == tokens.size() - 1;
            common_batch_add(
                g_batch,
                tokens[token_index],
                start_position + static_cast<llama_pos>(token_index),
                {0},
                want_logits);
        }

        if (llama_decode(g_context, g_batch) != 0) {
            set_last_error("llama.cpp failed while processing the prompt.");
            return false;
        }
    }

    return true;
}

std::string format_user_prompt(const std::string & prompt) {
    // Parsing arbitrary embedded Jinja templates on-device can make model load
    // unbounded on lower-end Android hardware. Use a small, known envelope for
    // ChatML models and a plain instruction prompt as the safe fallback.
    const char * chat_template = llama_model_chat_template(g_model, nullptr);
    if (chat_template != nullptr && std::strstr(chat_template, "<|im_start|>") != nullptr) {
        return "<|im_start|>user\n" + prompt + "<|im_end|>\n<|im_start|>assistant\n";
    }
    return prompt;
}

bool emit_java_message(
        JNIEnv * env,
        jobject bridge,
        jmethodID method_id,
        const std::string & request_id,
        const std::string & payload = "") {
    if (method_id == nullptr) {
        return false;
    }

    jstring request_id_java = utf8_to_jstring(env, request_id);
    jstring payload_java = payload.empty() ? nullptr : utf8_to_jstring(env, payload);
    env->CallVoidMethod(bridge, method_id, request_id_java, payload_java);
    env->DeleteLocalRef(request_id_java);
    if (payload_java != nullptr) {
        env->DeleteLocalRef(payload_java);
    }
    return env->ExceptionCheck() == JNI_FALSE;
}

bool emit_java_signal(
        JNIEnv * env,
        jobject bridge,
        jmethodID method_id,
        const std::string & request_id) {
    if (method_id == nullptr) {
        return false;
    }

    jstring request_id_java = utf8_to_jstring(env, request_id);
    env->CallVoidMethod(bridge, method_id, request_id_java);
    env->DeleteLocalRef(request_id_java);
    return env->ExceptionCheck() == JNI_FALSE;
}

bool stream_completion_locked(
        JNIEnv * env,
        jobject bridge,
        jmethodID token_method,
        jmethodID completed_method,
        jmethodID failed_method,
        jmethodID cancelled_method,
        const std::string & request_id,
        const std::string & prompt,
        const GenerationOptions & options) {
    if (g_model == nullptr || g_context == nullptr) {
        emit_java_message(env, bridge, failed_method, request_id, "Model is not loaded.");
        return false;
    }

    g_cancel_requested.store(false);
    if (g_sampler != nullptr) {
        common_sampler_free(g_sampler);
        g_sampler = nullptr;
    }

    common_params_sampling sampling_params;
    sampling_params.temp = options.temperature;
    sampling_params.top_k = options.top_k;
    sampling_params.top_p = options.top_p;
    sampling_params.min_p = 0.05f;
    sampling_params.penalty_repeat = 1.05f;
    sampling_params.penalty_last_n = 64;
    sampling_params.n_prev = 64;
    g_sampler = common_sampler_init(g_model, sampling_params);
    if (g_sampler == nullptr) {
        set_last_error("llama.cpp failed to initialize the sampler for this request.");
        emit_java_message(env, bridge, failed_method, request_id, g_last_error);
        return false;
    }

    common_sampler_reset(g_sampler);
    __android_log_write(ANDROID_LOG_INFO, kLogTag, "sampler ready");
    llama_memory_clear(llama_get_memory(g_context), false);

    const std::string formatted_prompt = format_user_prompt(prompt);
    const bool parse_special = true;
    const auto prompt_tokens = common_tokenize(g_context, formatted_prompt, parse_special, parse_special);
    __android_log_print(ANDROID_LOG_INFO, kLogTag, "prompt tokenized: %zu tokens", prompt_tokens.size());
    if (prompt_tokens.empty()) {
        set_last_error("Prompt was empty after tokenization.");
        emit_java_message(env, bridge, failed_method, request_id, g_last_error);
        return false;
    }

    if (!decode_tokens(prompt_tokens, 0, true)) {
        emit_java_message(env, bridge, failed_method, request_id, g_last_error);
        return false;
    }

    std::string assembled;
    std::string utf8_cache;
    llama_pos current_position = static_cast<llama_pos>(prompt_tokens.size());

    for (int i = 0; i < options.max_tokens; ++i) {
        if (g_cancel_requested.load()) {
            emit_java_signal(env, bridge, cancelled_method, request_id);
            return true;
        }

        const llama_token token_id = common_sampler_sample(g_sampler, g_context, -1);
        common_sampler_accept(g_sampler, token_id, true);

        if (llama_vocab_is_eog(llama_model_get_vocab(g_model), token_id)) {
            break;
        }

        common_batch_clear(g_batch);
        common_batch_add(g_batch, token_id, current_position, {0}, true);
        if (llama_decode(g_context, g_batch) != 0) {
            set_last_error("llama.cpp failed during token generation.");
            emit_java_message(env, bridge, failed_method, request_id, g_last_error);
            return false;
        }

        current_position += 1;
        utf8_cache += common_token_to_piece(g_context, token_id);

        if (is_valid_utf8(utf8_cache.c_str())) {
            assembled += utf8_cache;
            emit_java_message(env, bridge, token_method, request_id, utf8_cache);
            utf8_cache.clear();
        }
    }

    if (assembled.empty()) {
        assembled = "(no visible response)";
    } else {
        assembled = finish_at_sentence_boundary(assembled);
    }

    emit_java_message(env, bridge, completed_method, request_id, assembled);
    return true;
}
}  // namespace

extern "C"
JNIEXPORT jstring JNICALL
Java_io_instance001_chatty_1venture_NativeLlamaBridge_nativeGetEngineInfo(
        JNIEnv * env,
        jobject /* this */) {
    ensure_backend_initialized();
    const char * info = llama_print_system_info();
    return utf8_to_jstring(env, info != nullptr ? info : "llama.cpp runtime ready");
}

extern "C"
JNIEXPORT jboolean JNICALL
Java_io_instance001_chatty_1venture_NativeLlamaBridge_nativeLoadModel(
        JNIEnv * env,
        jobject /* this */,
        jstring modelPath,
        jint contextSize,
        jint gpuLayers) {
    if (modelPath == nullptr) {
        return JNI_FALSE;
    }

    const std::string model_path = jstring_to_utf8(env, modelPath);
    if (model_path.empty()) {
        return JNI_FALSE;
    }

    std::lock_guard<std::mutex> lock(g_mutex);
    const bool loaded = load_model_locked(model_path, contextSize, gpuLayers);
    return loaded ? JNI_TRUE : JNI_FALSE;
}

extern "C"
JNIEXPORT jstring JNICALL
Java_io_instance001_chatty_1venture_NativeLlamaBridge_nativeGetLastError(
        JNIEnv * env,
        jobject /* this */) {
    const std::string message = g_last_error.empty()
        ? "Native inference error details are unavailable."
        : g_last_error;
    return utf8_to_jstring(env, message);
}

extern "C"
JNIEXPORT jboolean JNICALL
Java_io_instance001_chatty_1venture_NativeLlamaBridge_nativeStartGeneration(
        JNIEnv * env,
        jobject thiz,
        jstring requestId,
        jstring modelPath,
        jstring prompt,
        jint contextSize,
        jint maxTokens,
        jdouble temperature,
        jdouble topP,
        jint topK,
        jint gpuLayers) {
    if (requestId == nullptr || modelPath == nullptr || prompt == nullptr) {
        return JNI_FALSE;
    }

    jclass bridge_class = env->GetObjectClass(thiz);
    const jmethodID token_method = env->GetMethodID(
        bridge_class,
        "onNativeToken",
        "(Ljava/lang/String;Ljava/lang/String;)V");
    const jmethodID completed_method = env->GetMethodID(
        bridge_class,
        "onNativeCompleted",
        "(Ljava/lang/String;Ljava/lang/String;)V");
    const jmethodID failed_method = env->GetMethodID(
        bridge_class,
        "onNativeFailed",
        "(Ljava/lang/String;Ljava/lang/String;)V");
    const jmethodID cancelled_method = env->GetMethodID(
        bridge_class,
        "onNativeCancelled",
        "(Ljava/lang/String;)V");

    const std::string request_id = jstring_to_utf8(env, requestId);
    const std::string model_path = jstring_to_utf8(env, modelPath);
    const std::string prompt_text = jstring_to_utf8(env, prompt);
    if (request_id.empty() || model_path.empty()) {
        return JNI_FALSE;
    }

    GenerationOptions options;
    options.context_size = contextSize > 0 ? contextSize : kDefaultContextSize;
    options.max_tokens = maxTokens > 0 ? maxTokens : kDefaultPredictTokens;
    options.temperature = temperature > 0.0 ? static_cast<float>(temperature) : kDefaultTemperature;
    options.top_p = topP > 0.0 ? static_cast<float>(topP) : 0.95f;
    options.top_k = topK > 0 ? topK : 40;
    options.gpu_layers = gpuLayers;

    std::lock_guard<std::mutex> lock(g_mutex);
    if (!load_model_locked(model_path, options.context_size, options.gpu_layers)) {
        emit_java_message(
            env,
            thiz,
            failed_method,
            request_id,
            "Failed to load the selected GGUF model.");
        return JNI_FALSE;
    }

    const bool ok = stream_completion_locked(
        env,
        thiz,
        token_method,
        completed_method,
        failed_method,
        cancelled_method,
        request_id,
        prompt_text,
        options);
    return ok ? JNI_TRUE : JNI_FALSE;
}

extern "C"
JNIEXPORT void JNICALL
Java_io_instance001_chatty_1venture_NativeLlamaBridge_nativeRequestCancel(
        JNIEnv * /* env */,
        jobject /* this */) {
    g_cancel_requested.store(true);
}

extern "C"
JNIEXPORT void JNICALL
Java_io_instance001_chatty_1venture_NativeLlamaBridge_nativeUnloadModel(
        JNIEnv * /* env */,
        jobject /* this */) {
    std::lock_guard<std::mutex> lock(g_mutex);
    unload_locked();
}
