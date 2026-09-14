package io.instance001.chatty_venture

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class CloudKeyBridge(context: Context) {
    private val prefs = context.getSharedPreferences("cloud_key_store", Context.MODE_PRIVATE)
    private val alias = "chatty_venture_cloud_keys"
    fun save(id: String, value: String) { val cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key()); prefs.edit().putString(id, Base64.encodeToString(cipher.iv + cipher.doFinal(value.toByteArray()), Base64.NO_WRAP)).apply() }
    fun read(id: String): String? { val bytes = Base64.decode(prefs.getString(id, null) ?: return null, Base64.NO_WRAP); if (bytes.size <= 12) return null; val cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12))); return String(cipher.doFinal(bytes.copyOfRange(12, bytes.size))) }
    fun delete(id: String) { prefs.edit().remove(id).apply() }
    fun has(id: String) = prefs.contains(id)
    private fun key(): SecretKey { val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }; (store.getKey(alias, null) as? SecretKey)?.let { return it }; return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply { init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build()) }.generateKey() }
}
