package com.example.anigen

import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    // Each handshake identifies a listener, including after a Dart restart.
    private var dartListener: Any? = null
    private var resumed = false
    private val installTokens by lazy { getSharedPreferences("update_sessions", MODE_PRIVATE) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        dartListener = null
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "abis" -> result.success(Build.SUPPORTED_ABIS.toList())
                    "takePendingInstallFailure" -> {
                        dartListener = Any()
                        installStatusListeners.add(this@MainActivity)
                        result.success(null)
                        deliverInstallFailures()
                    }
                    "canInstall" -> result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            packageManager.canRequestPackageInstalls()
                    )
                    "openInstallSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName")
                                )
                            )
                        }
                        result.success(null)
                    }
                    "install" -> {
                        val path = call.argument<String>("path")!!
                        // Copying the APK into the session is disk work
                        thread {
                            try {
                                install(File(path))
                                runOnUiThread { result.success(null) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("install", e.message, null) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /// Hands the APK to the system installer, which asks the user to confirm.
    private fun install(apk: File) {
        val installer = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL
        ).apply { setAppPackageName(packageName) }
        val id = installer.createSession(params)
        installer.openSession(id).use { session ->
            val token = UUID.randomUUID().toString()
            try {
                apk.inputStream().use { input ->
                    session.openWrite("anigen.apk", 0, apk.length()).use { output ->
                        input.copyTo(output)
                        session.fsync(output)
                    }
                }
                // MainActivity is exported, so authenticate callbacks across process restarts.
                check(installTokens.edit().putBoolean(token, true).commit())
                val intent = Intent(this, MainActivity::class.java)
                    .setAction(ACTION_INSTALL_STATUS)
                    .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    .putExtra(EXTRA_INSTALL_TOKEN, token)
                // The system fills in the status extras, so it has to be mutable
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                    (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
                val pending = PendingIntent.getActivity(this, id, intent, flags)
                session.commit(pending.intentSender)
            } catch (e: Exception) {
                runCatching { session.abandon() }.exceptionOrNull()?.let(e::addSuppressed)
                installTokens.edit().remove(token).apply()
                throw e
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        installStatusListeners.remove(this)
        if (installFailureDelivery === channel) installFailureDelivery = null
        channel?.setMethodCallHandler(null)
        channel = null
        dartListener = null
        super.cleanUpFlutterEngine(flutterEngine)
        deliverInstallFailures()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleInstallStatus(intent, showConfirmation = savedInstanceState == null)
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        deliverInstallFailures()
    }

    override fun onPause() {
        resumed = false
        super.onPause()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleInstallStatus(intent)
    }

    private fun handleInstallStatus(intent: Intent?, showConfirmation: Boolean = true) {
        if (intent?.action != ACTION_INSTALL_STATUS || !intent.hasExtra(PackageInstaller.EXTRA_STATUS)) return
        val token = intent.getStringExtra(EXTRA_INSTALL_TOKEN) ?: return
        if (!installTokens.getBoolean(token, false)) return
        when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -1)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                if (!showConfirmation) return
                val confirm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                confirm?.let { startActivity(it) }
            }
            PackageInstaller.STATUS_SUCCESS -> installTokens.edit().remove(token).apply()
            else -> {
                installTokens.edit().remove(token).apply()
                pendingInstallFailures.addLast(
                    mapOf(
                        "status" to status,
                        "message" to intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE),
                    )
                )
                deliverInstallFailures()
            }
        }
    }

    private fun sendNextInstallFailure() {
        val live = channel ?: return
        val listener = dartListener ?: return
        val failure = pendingInstallFailures.firstOrNull() ?: return
        if (installFailureDelivery != null) return

        // Keep the failure queued until Dart acknowledges it. Send one at a time
        // so Flutter's channel buffer can't discard concurrent failures.
        installFailureDelivery = live
        live.invokeMethod("installFailed", failure, object : MethodChannel.Result {
            override fun success(result: Any?) = finish(delivered = true)
            override fun error(code: String, message: String?, details: Any?) = finish(delivered = false)
            override fun notImplemented() = finish(delivered = false)

            private fun finish(delivered: Boolean) {
                if (installFailureDelivery !== live) return
                installFailureDelivery = null
                if (delivered) {
                    pendingInstallFailures.removeFirst()
                } else if (dartListener === listener) {
                    dartListener = null
                    installStatusListeners.remove(this@MainActivity)
                }
                deliverInstallFailures()
            }
        })
    }

    companion object {
        // Activity lifecycle and channel callbacks access this queue on the main thread.
        private val pendingInstallFailures = ArrayDeque<Map<String, Any?>>()
        private val installStatusListeners = mutableSetOf<MainActivity>()
        private var installFailureDelivery: MethodChannel? = null

        private fun deliverInstallFailures() {
            installStatusListeners.firstOrNull { it.resumed }?.sendNextInstallFailure()
        }

        private const val CHANNEL = "anigen/update"
        private const val ACTION_INSTALL_STATUS = "com.example.anigen.INSTALL_STATUS"
        private const val EXTRA_INSTALL_TOKEN = "com.example.anigen.INSTALL_TOKEN"
    }
}
