package ai.nhai.biometric.rn

/**
 * Android native bridge: exposes the embedded Flutter biometric engine to React
 * Native as the `NhaiBiometric` native module.
 *
 * It hosts a cached [FlutterEngine] (so the TFLite model stays warm) and
 * forwards each JS call over the `ai.nhai.biometric/sdk` MethodChannel to the
 * Dart `NhaiSdkChannel`/`NhaiSdkBridge`. Non-OK SdkResults reject the JS
 * promise with the stable code so the JS wrapper can map them to `SdkError`.
 *
 * Illustrative integration stub for the demo — wire-up only, no AI logic.
 */
import com.facebook.react.bridge.*
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

private const val ENGINE_ID = "nhai_biometric_engine"
private const val CHANNEL = "ai.nhai.biometric/sdk"

class NhaiBiometricModule(private val ctx: ReactApplicationContext) :
    ReactContextBaseJavaModule(ctx) {

  override fun getName() = "NhaiBiometric"

  private val channel: MethodChannel by lazy {
    // The engine is pre-warmed at app start (see registerEngine) so the model
    // loads once and survives across calls.
    val engine = FlutterEngineCache.getInstance().get(ENGINE_ID)
        ?: FlutterEngine(ctx).also {
          it.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
          FlutterEngineCache.getInstance().put(ENGINE_ID, it)
        }
    MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
  }

  private fun invoke(method: String, args: ReadableMap, promise: Promise) {
    val payload = args.toHashMap()
    runOnUiThread {
      channel.invokeMethod(method, payload, object : MethodChannel.Result {
        override fun success(result: Any?) {
          @Suppress("UNCHECKED_CAST")
          val map = result as? Map<String, Any?> ?: emptyMap()
          if (map["ok"] == true) {
            promise.resolve(Arguments.makeNativeMap(map["data"] as? Map<String, Any?> ?: emptyMap()))
          } else {
            promise.reject(map["code"] as? String ?: "ERROR", map["message"] as? String)
          }
        }
        override fun error(code: String, message: String?, details: Any?) =
            promise.reject(code, message)
        override fun notImplemented() = promise.reject("UNKNOWN_METHOD", method)
      })
    }
  }

  @ReactMethod fun enrollEmployee(args: ReadableMap, p: Promise) = invoke("enrollEmployee", args, p)
  @ReactMethod fun authenticateEmployee(args: ReadableMap, p: Promise) = invoke("authenticateEmployee", args, p)
  @ReactMethod fun markAttendance(args: ReadableMap, p: Promise) = invoke("markAttendance", args, p)
  @ReactMethod fun getAttendanceSummary(args: ReadableMap, p: Promise) = invoke("getAttendanceSummary", args, p)
  @ReactMethod fun syncRecords(args: ReadableMap, p: Promise) = invoke("syncRecords", args, p)

  private fun runOnUiThread(block: () -> Unit) =
      ctx.runOnUiQueueThread(block)
}
