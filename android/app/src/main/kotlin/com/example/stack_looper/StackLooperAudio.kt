package com.example.stack_looper

import android.os.Handler
import android.os.HandlerThread
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Kotlin bridge between Flutter (via MethodChannel) and our native C++ audio
 * engine (via JNI). This class is deliberately thin — it only translates
 * MethodChannel calls into JNI calls. All audio logic lives in C++.
 *
 * Native library name must match the CMake target (stack_looper_engine).
 */
class StackLooperAudio(flutterEngine: FlutterEngine) {

    companion object {
        private const val CHANNEL = "stack_looper/audio"
        private const val EVENTS_CHANNEL = "stack_looper/audio_events"

        init {
            System.loadLibrary("stack_looper_engine")
        }

        // Defined in jni_bridge.cpp.
        @JvmStatic external fun nativeVersion(): String
        @JvmStatic external fun nativeStart(): Int
        @JvmStatic external fun nativeStop()
        @JvmStatic external fun nativeSampleRate(): Int
        @JvmStatic external fun nativeIsRunning(): Boolean
        @JvmStatic external fun nativeSetTempoBpm(bpm: Double)
        @JvmStatic external fun nativeStartMetronome()
        @JvmStatic external fun nativeStopMetronome()
        @JvmStatic external fun nativeSetMetronomeAudible(audible: Boolean)
        @JvmStatic external fun nativeCurrentFrame(): Long
        @JvmStatic external fun nativeSamplesPerBeat(): Int
        @JvmStatic external fun nativeCurrentBeat(): Long
        @JvmStatic external fun nativeNextClickFrame(): Long
        @JvmStatic external fun nativeArmRecording(
            trackId: Int, startFrame: Long, lengthFrames: Int,
        ): Boolean
        @JvmStatic external fun nativeTrackState(trackId: Int): Int
        @JvmStatic external fun nativeTrackRecordedSamples(trackId: Int): Int
        @JvmStatic external fun nativeTrackWaveformPeaks(trackId: Int, bucketCount: Int): FloatArray
        @JvmStatic external fun nativeStartTrackPlayback(trackId: Int)
        @JvmStatic external fun nativeStopTrackPlayback(trackId: Int)
        @JvmStatic external fun nativeIsTrackPlaying(trackId: Int): Boolean
        @JvmStatic external fun nativeClearTrack(trackId: Int)
    }

    private val channel = MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        CHANNEL,
    )

    private val eventChannel = EventChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        EVENTS_CHANNEL,
    )

    // Beat poll thread. Runs off the audio callback so JNI/Flutter work never
    // happens in the real-time audio path. Polls at ~60 Hz — fast enough that
    // UI beat flashes look tight (<17 ms lag) but cheap.
    private var pollThread: HandlerThread? = null
    private var pollHandler: Handler? = null
    private var pollRunnable: Runnable? = null
    private var eventSink: EventChannel.EventSink? = null
    private var lastBeatSent: Long = -1
    private val mainHandler = Handler(android.os.Looper.getMainLooper())

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "version" -> result.success(nativeVersion())
                "start" -> {
                    val code = nativeStart()
                    if (code == 0) {
                        startBeatPoll()
                        result.success(null)
                    } else {
                        result.error("START_FAILED", "oboe result=$code", null)
                    }
                }
                "stop" -> {
                    stopBeatPoll()
                    nativeStop()
                    result.success(null)
                }
                "sampleRate" -> result.success(nativeSampleRate())
                "isRunning" -> result.success(nativeIsRunning())
                "setTempoBpm" -> {
                    val bpm = (call.arguments as? Number)?.toDouble()
                    if (bpm == null) {
                        result.error("BAD_ARGS", "setTempoBpm expects a number", null)
                    } else {
                        nativeSetTempoBpm(bpm)
                        result.success(null)
                    }
                }
                "startMetronome" -> {
                    nativeStartMetronome()
                    result.success(null)
                }
                "stopMetronome" -> {
                    nativeStopMetronome()
                    result.success(null)
                }
                "setMetronomeAudible" -> {
                    val audible = call.arguments as? Boolean
                    if (audible == null) {
                        result.error("BAD_ARGS", "setMetronomeAudible expects bool", null)
                    } else {
                        nativeSetMetronomeAudible(audible)
                        result.success(null)
                    }
                }
                "currentFrame" -> result.success(nativeCurrentFrame())
                "samplesPerBeat" -> result.success(nativeSamplesPerBeat())
                "currentBeat" -> result.success(nativeCurrentBeat())
                "nextClickFrame" -> result.success(nativeNextClickFrame())
                "armRecording" -> {
                    val args = call.arguments as? Map<*, *>
                    val trackId = (args?.get("trackId") as? Number)?.toInt()
                    val startFrame = (args?.get("startFrame") as? Number)?.toLong()
                    val lengthFrames = (args?.get("lengthFrames") as? Number)?.toInt()
                    if (trackId == null || startFrame == null || lengthFrames == null) {
                        result.error("BAD_ARGS",
                            "armRecording expects {trackId, startFrame, lengthFrames}", null)
                    } else {
                        val ok = nativeArmRecording(trackId, startFrame, lengthFrames)
                        result.success(ok)
                    }
                }
                "trackState" -> {
                    val id = (call.arguments as? Number)?.toInt()
                    if (id == null) result.error("BAD_ARGS", "trackState expects int", null)
                    else result.success(nativeTrackState(id))
                }
                "trackRecordedSamples" -> {
                    val id = (call.arguments as? Number)?.toInt()
                    if (id == null) result.error("BAD_ARGS", "trackRecordedSamples expects int", null)
                    else result.success(nativeTrackRecordedSamples(id))
                }
                "trackWaveformPeaks" -> {
                    val args = call.arguments as? Map<*, *>
                    val id = (args?.get("trackId") as? Number)?.toInt()
                    val bucketCount = (args?.get("bucketCount") as? Number)?.toInt()
                    if (id == null || bucketCount == null) {
                        result.error("BAD_ARGS", "trackWaveformPeaks expects {trackId, bucketCount}", null)
                    } else {
                        result.success(nativeTrackWaveformPeaks(id, bucketCount).toList())
                    }
                }
                "startTrackPlayback" -> {
                    val id = (call.arguments as? Number)?.toInt()
                    if (id == null) result.error("BAD_ARGS", "startTrackPlayback expects int", null)
                    else { nativeStartTrackPlayback(id); result.success(null) }
                }
                "stopTrackPlayback" -> {
                    val id = (call.arguments as? Number)?.toInt()
                    if (id == null) result.error("BAD_ARGS", "stopTrackPlayback expects int", null)
                    else { nativeStopTrackPlayback(id); result.success(null) }
                }
                "isTrackPlaying" -> {
                    val id = (call.arguments as? Number)?.toInt()
                    if (id == null) result.error("BAD_ARGS", "isTrackPlaying expects int", null)
                    else result.success(nativeIsTrackPlaying(id))
                }
                "clearTrack" -> {
                    val id = (call.arguments as? Number)?.toInt()
                    if (id == null) result.error("BAD_ARGS", "clearTrack expects int", null)
                    else { nativeClearTrack(id); result.success(null) }
                }
                else -> result.notImplemented()
            }
        }

        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                // Seed to the CURRENT beat count (not current-1). We only
                // want to emit events for beats that happen AFTER this
                // subscription; using -1 would immediately emit the pre-
                // existing value as a phantom event, shifting the caller's
                // beat counting by one.
                lastBeatSent = nativeCurrentBeat()
            }
            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    private fun startBeatPoll() {
        if (pollThread != null) return
        val t = HandlerThread("StackLooperBeatPoll").apply { start() }
        val h = Handler(t.looper)
        val r = object : Runnable {
            override fun run() {
                val beat = nativeCurrentBeat()
                if (beat != lastBeatSent) {
                    lastBeatSent = beat
                    // EventSink must be called on the main/UI thread.
                    val sink = eventSink
                    if (sink != null) {
                        mainHandler.post { sink.success(beat) }
                    }
                }
                h.postDelayed(this, 16L)  // ~60 Hz
            }
        }
        h.post(r)
        pollThread = t
        pollHandler = h
        pollRunnable = r
    }

    private fun stopBeatPoll() {
        pollRunnable?.let { pollHandler?.removeCallbacks(it) }
        pollThread?.quitSafely()
        pollThread = null
        pollHandler = null
        pollRunnable = null
    }
}
