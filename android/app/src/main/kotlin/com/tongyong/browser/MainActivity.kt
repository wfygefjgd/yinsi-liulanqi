package com.tongyong.browser

import android.os.Process
import android.webkit.CookieManager
import android.webkit.WebStorage
import android.webkit.WebView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "privacy_browser/engine"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "nuclearWipe" -> {
                        nuclearWipe()
                        result.success(null)
                    }
                    "exitApp" -> {
                        // Only used by manual clear
                        result.success(null)
                        window.decorView.postDelayed({
                            finishAndRemoveTask()
                            Process.killProcess(Process.myPid())
                        }, 80)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun nuclearWipe() {
        try {
            CookieManager.getInstance().removeAllCookies(null)
            CookieManager.getInstance().flush()
        } catch (_: Exception) {
        }
        try {
            WebStorage.getInstance().deleteAllData()
        } catch (_: Exception) {
        }
        try {
            WebView(this).apply {
                clearCache(true)
                clearFormData()
                clearHistory()
                clearSslPreferences()
                clearMatches()
                destroy()
            }
        } catch (_: Exception) {
        }

        deleteRecursively(cacheDir)
        deleteRecursively(codeCacheDir)
        deleteRecursively(externalCacheDir)
        deleteRecursively(filesDir)
        deleteRecursively(getDir("webview", MODE_PRIVATE))
        deleteRecursively(getDir("app_webview", MODE_PRIVATE))
        deleteRecursively(File(applicationInfo.dataDir, "app_webview"))
        deleteRecursively(File(applicationInfo.dataDir, "app_flutter"))
        deleteRecursively(File(applicationInfo.dataDir, "cache"))
        deleteRecursively(File(applicationInfo.dataDir, "code_cache"))
        deleteRecursively(File(applicationInfo.dataDir, "databases"))
        deleteRecursively(File(applicationInfo.dataDir, "no_backup"))

        getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            .edit()
            .clear()
            .commit()
        val prefsDir = File(applicationInfo.dataDir, "shared_prefs")
        prefsDir.listFiles()?.forEach { it.delete() }
        databaseList()?.forEach { deleteDatabase(it) }
    }

    private fun deleteRecursively(file: File?) {
        if (file == null || !file.exists()) return
        if (file.isDirectory) {
            file.listFiles()?.forEach { deleteRecursively(it) }
        }
        file.delete()
    }
}
