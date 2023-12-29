package com.hiddify.hiddify

import android.util.Log
import com.hiddify.hiddify.bg.BoxService
import com.hiddify.hiddify.constant.Status
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.nekohasekai.libbox.Libbox
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class MethodHandler(private val scope: CoroutineScope) : FlutterPlugin,
        MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null

    companion object {
        const val TAG = "A/MethodHandler"
        const val channelName = "com.hiddify.app/method"

        enum class Trigger(val method: String) {
            ParseConfig("parse_config"),
            ChangeConfigOptions("change_config_options"),
            GenerateConfig("generate_config"),
            Start("start"),
            Stop("stop"),
            Restart("restart"),
            SelectOutbound("select_outbound"),
            UrlTest("url_test"),
            ClearLogs("clear_logs"),
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(
                flutterPluginBinding.binaryMessenger,
                channelName,
        )
        channel!!.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            Trigger.ParseConfig.method -> {
                scope.launch(Dispatchers.IO) {
                    result.runCatching {
                        val args = call.arguments as Map<*, *>
                        val path = args["path"] as String
                        val tempPath = args["tempPath"] as String
                        val debug = args["debug"] as Boolean
                        val msg = BoxService.parseConfig(path, tempPath, debug)
                        success(msg)
                    }
                }
            }

            Trigger.ChangeConfigOptions.method -> {
                scope.launch {
                    result.runCatching {
                        val args = call.arguments as String
                        Settings.configOptions = args
                        success(true)
                    }
                }
            }

            Trigger.GenerateConfig.method -> {
                scope.launch {
                    result.runCatching {
                        val args = call.arguments as Map<*, *>
                        val path = args["path"] as String
                        val options = Settings.configOptions
                        if (options.isBlank() || path.isBlank()) {
                            error("blank properties")
                        }
                        val config = BoxService.buildConfig(path, options)
                        success(config)
                    }
                }
            }

            Trigger.Start.method -> {
                scope.launch {
                    result.runCatching {
                        val args = call.arguments as Map<*, *>
                        Settings.activeConfigPath = args["path"] as String? ?: ""
                        Settings.activeProfileName = args["name"] as String? ?: ""
                        val mainActivity = MainActivity.instance
                        val started = mainActivity.serviceStatus.value == Status.Started
                        if (started) {
                            Log.w(TAG, "service is already running")
                            return@launch success(true)
                        }
                        mainActivity.startService()
                        success(true)
                    }
                }
            }

            Trigger.Stop.method -> {
                scope.launch {
                    result.runCatching {
                        val mainActivity = MainActivity.instance
                        val started = mainActivity.serviceStatus.value == Status.Started
                        if (!started) {
                            Log.w(TAG, "service is not running")
                            return@launch success(true)
                        }
                        BoxService.stop()
                        success(true)
                    }
                }
            }

            Trigger.Restart.method -> {
                scope.launch(Dispatchers.IO) {
                    result.runCatching {
                        val args = call.arguments as Map<*, *>
                        Settings.activeConfigPath = args["path"] as String? ?: ""
                        Settings.activeProfileName = args["name"] as String? ?: ""
                        val mainActivity = MainActivity.instance
                        val started = mainActivity.serviceStatus.value == Status.Started
                        if (!started) return@launch success(true)
                        val restart = Settings.rebuildServiceMode()
                        if (restart) {
                            mainActivity.reconnect()
                            BoxService.stop()
                            delay(1000L)
                            mainActivity.startService()
                            return@launch success(true)
                        }
                        runCatching {
                            Libbox.newStandaloneCommandClient().serviceReload()
                            success(true)
                        }.onFailure {
                            error(it)
                        }
                    }
                }
            }

            Trigger.SelectOutbound.method -> {
                scope.launch {
                    result.runCatching {
                        val args = call.arguments as Map<*, *>
                        Libbox.newStandaloneCommandClient()
                                .selectOutbound(
                                        args["groupTag"] as String,
                                        args["outboundTag"] as String
                                )
                        success(true)
                    }
                }
            }

            Trigger.UrlTest.method -> {
                scope.launch {
                    result.runCatching {
                        val args = call.arguments as Map<*, *>
                        Libbox.newStandaloneCommandClient()
                                .urlTest(
                                        args["groupTag"] as String
                                )
                        success(true)
                    }
                }
            }

            Trigger.ClearLogs.method -> {
                scope.launch {
                    result.runCatching {
                        MainActivity.instance.onServiceResetLogs(mutableListOf())
                        success(true)
                    }
                }
            }

            else -> result.notImplemented()
        }
    }
}