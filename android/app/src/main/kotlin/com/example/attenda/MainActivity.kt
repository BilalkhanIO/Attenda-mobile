package com.example.attenda

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import java.security.spec.ECGenParameterSpec

class MainActivity : FlutterActivity() {
    private val channelName = "app.attenda/attendance_device_keys"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "generate" -> {
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                                result.error("UNSUPPORTED", "Secure attendance keys require Android 6.0 or later.", null)
                                return@setMethodCallHandler
                            }
                            val alias = call.argument<String>("alias") ?: throw IllegalArgumentException("Missing key alias")
                            val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                            if (!store.containsAlias(alias)) {
                                val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore")
                                generator.initialize(
                                    KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
                                        .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                                        .setDigests(KeyProperties.DIGEST_SHA256)
                                        .setUserAuthenticationRequired(false)
                                        .build()
                                )
                                generator.generateKeyPair()
                            }
                            val certificate = store.getCertificate(alias) ?: throw IllegalStateException("Device key certificate is missing")
                            result.success(Base64.encodeToString(certificate.publicKey.encoded, Base64.NO_WRAP))
                        }
                        "sign" -> {
                            val alias = call.argument<String>("alias") ?: throw IllegalArgumentException("Missing key alias")
                            val message = call.argument<String>("message") ?: throw IllegalArgumentException("Missing message")
                            val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                            val privateKey = store.getKey(alias, null) ?: throw IllegalStateException("Device key is unavailable")
                            val signer = Signature.getInstance("SHA256withECDSA")
                            signer.initSign(privateKey as java.security.PrivateKey)
                            signer.update(message.toByteArray(Charsets.UTF_8))
                            result.success(Base64.encodeToString(signer.sign(), Base64.NO_WRAP))
                        }
                        "delete" -> {
                            val alias = call.argument<String>("alias") ?: throw IllegalArgumentException("Missing key alias")
                            val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                            if (store.containsAlias(alias)) store.deleteEntry(alias)
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("DEVICE_KEY_ERROR", error.message ?: "Secure device key operation failed.", null)
                }
            }
    }
}
