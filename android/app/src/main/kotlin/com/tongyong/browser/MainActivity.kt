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
    private val durableName = "durable"

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
                        result.success(null)
                        window.decorView.postDelayed({
                            finishAndRemoveTask()
                            Process.killProcess(Process.myPid())
                        }, 120)
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
                destroy()
            }
        } catch (_: Exception) {
        }

        deleteRecursivelyPreserve(cacheDir, null)
        deleteRecursivelyPreserve(codeCacheDir, null)
        deleteRecursivelyPreserve(externalCacheDir, null)
        // Keep app_flutter/durable or filesDir/durable bookmarks.
        deleteRecursivelyPreserve(filesDir, durableName)
        deleteRecursivelyPreserve(getDir("webview", MODE_PRIVATE), null)
        deleteRecursivelyPreserve(getDir("app_webview", MODE_PRIVATE), null)
        deleteRecursivelyPreserve(File(applicationInfo.dataDir, "app_webview"), null)
        deleteRecursivelyPreserve(File(applicationInfo.dataDir, "cache"), null)
        deleteRecursivelyPreserve(File(applicationInfo.dataDir, "code_cache"), null)

        // Clear flutter prefs except we store bookmarks in files, not prefs.
        getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            .edit()
            .clear()
            .commit()
        val prefsDir = File(applicationInfo.dataDir, "shared_prefs")
        prefsDir.listFiles()?.forEach { it.delete() }
        databaseList()?.forEach { deleteDatabase(it) }
    }

    private fun deleteRecursivelyPreserve(file: File?, preserveChildName: String?) {
        if (file == null || !file.exists()) return
        if (file.isDirectory) {
            file.listFiles()?.forEach { child ->
                if (preserveChildName != null && child.name == preserveChildName) {
                    return@forEach
                }
                // Also preserve nested path .../app_flutter/durable or documents/durable
                if (preserveChildName != null && child.isDirectory) {
                    val durable = File(child, preserveChildName)
                    if (durable.exists()) {
                        child.listFiles()?.forEach { grand ->
                            if (grand.name != preserveChildName) {
                                deleteRecursivelyPreserve(grand, null)
                            }
                        }
                        return@forEach
                    }
                }
                deleteRecursivelyPreserve(child, null)
            }
            // do not delete root filesDir if we preserved children
            if (preserveChildName == null) {
                file.delete()
            } else {
                // leave directory
            }
        } else {
            file.delete()
        }
    }
}
