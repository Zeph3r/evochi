package com.evochi.evochi

import android.Manifest
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// A FlutterFragmentActivity (an androidx ComponentActivity), not the default FlutterActivity: the health plugin
// asks Health Connect for its permissions through registerForActivityResult, which only a ComponentActivity has.
// From a plain FlutterActivity it can never show Health Connect's dialog, so the request just comes back denied.
//
// It also counts steps live from the phone's own step counter (lib/data/health_adapters/live_steps.dart), for the
// first hatch: Health Connect only hears of steps when the phone's step tracker writes them in, which can be
// minutes later. "evochi/steps" answers whether there is a counter and asks for the physical-activity permission;
// "evochi/steps/live" streams the counter's running total (steps since the phone started) while it's listened to.
// Nothing is stored: the game's own record of your steps still comes from Health Connect.
class MainActivity : FlutterFragmentActivity() {
    private var pendingPermission: MethodChannel.Result? = null
    private var listener: SensorEventListener? = null

    private fun counter(): Sensor? =
        (getSystemService(SENSOR_SERVICE) as SensorManager?)?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)

    private fun permitted(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "evochi/steps").setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(counter() != null)
                "permission" -> {
                    if (permitted()) {
                        result.success(true)
                    } else if (pendingPermission != null) {
                        result.success(false)
                    } else {
                        pendingPermission = result
                        requestPermissions(arrayOf(Manifest.permission.ACTIVITY_RECOGNITION), STEPS_REQUEST)
                    }
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "evochi/steps/live").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                val sm = getSystemService(SENSOR_SERVICE) as SensorManager?
                val sensor = counter()
                if (sm == null || sensor == null || !permitted()) {
                    events.endOfStream()
                    return
                }
                stop()
                val l = object : SensorEventListener {
                    override fun onSensorChanged(event: SensorEvent) {
                        events.success(event.values[0].toLong())
                    }

                    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
                }
                listener = l
                sm.registerListener(l, sensor, SensorManager.SENSOR_DELAY_UI)
            }

            override fun onCancel(arguments: Any?) = stop()
        })
    }

    private fun stop() {
        val l = listener ?: return
        (getSystemService(SENSOR_SERVICE) as SensorManager?)?.unregisterListener(l)
        listener = null
    }

    @Deprecated("Deprecated in Java")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != STEPS_REQUEST) return
        val r = pendingPermission ?: return
        pendingPermission = null
        r.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
    }

    override fun onDestroy() {
        stop()
        super.onDestroy()
    }

    companion object {
        private const val STEPS_REQUEST = 4711
    }
}
