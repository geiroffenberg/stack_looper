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
        @JvmStatic external fun nativeSetMasterOutputGainDb(db: Float)
        @JvmStatic external fun nativeMasterOutputGainDb(): Float
        @JvmStatic external fun nativeSetLimiterCeilingDb(db: Float)
        @JvmStatic external fun nativeLimiterCeilingDb(): Float
        @JvmStatic external fun nativeSetTrackOutputGainDb(trackId: Int, db: Float)
        @JvmStatic external fun nativeTrackOutputGainDb(trackId: Int): Float
        @JvmStatic external fun nativeSetTrackDelaySendEnabled(trackId: Int, enabled: Boolean)
        @JvmStatic external fun nativeSetTrackReverbSendEnabled(trackId: Int, enabled: Boolean)
        @JvmStatic external fun nativeSetHighPassHz(hz: Float)
        @JvmStatic external fun nativeHighPassHz(): Float
        @JvmStatic external fun nativeSetLowPassHz(hz: Float)
        @JvmStatic external fun nativeLowPassHz(): Float
        @JvmStatic external fun nativeSetEqLowDb(db: Float)
        @JvmStatic external fun nativeEqLowDb(): Float
        @JvmStatic external fun nativeSetEqMidDb(db: Float)
        @JvmStatic external fun nativeEqMidDb(): Float
        @JvmStatic external fun nativeSetEqHighDb(db: Float)
        @JvmStatic external fun nativeEqHighDb(): Float
        @JvmStatic external fun nativeSetCompressorAmount(amount: Float)
        @JvmStatic external fun nativeCompressorAmount(): Float
        @JvmStatic external fun nativeSetDistortionAmount(amount: Float)
        @JvmStatic external fun nativeDistortionAmount(): Float
        @JvmStatic external fun nativeSetSaturationAmount(amount: Float)
        @JvmStatic external fun nativeSaturationAmount(): Float
        @JvmStatic external fun nativeSetDelaySend(amount: Float)
        @JvmStatic external fun nativeDelaySend(): Float
        @JvmStatic external fun nativeSetDelayDivision(division: Int)
        @JvmStatic external fun nativeDelayDivision(): Int
        @JvmStatic external fun nativeSetDelayFeel(feel: Int)
        @JvmStatic external fun nativeDelayFeel(): Int
        @JvmStatic external fun nativeSetReverbSend(amount: Float)
        @JvmStatic external fun nativeReverbSend(): Float
        @JvmStatic external fun nativeSetReverbRoomSize(amount: Float)
        @JvmStatic external fun nativeReverbRoomSize(): Float
        @JvmStatic external fun nativeSetDjFilterAmount(amount: Float)
        @JvmStatic external fun nativeDjFilterAmount(): Float
        @JvmStatic external fun nativeSetDjFilterResonance(amount: Float)
        @JvmStatic external fun nativeDjFilterResonance(): Float
        @JvmStatic external fun nativeSetBeatRepeatMix(amount: Float)
        @JvmStatic external fun nativeBeatRepeatMix(): Float
        @JvmStatic external fun nativeSetBeatRepeatDivision(division: Int)
        @JvmStatic external fun nativeBeatRepeatDivision(): Int
        @JvmStatic external fun nativeSetTransGateAmount(amount: Float)
        @JvmStatic external fun nativeTransGateAmount(): Float
        @JvmStatic external fun nativeSetTransGateDivision(division: Int)
        @JvmStatic external fun nativeTransGateDivision(): Int
        @JvmStatic external fun nativeSetNoiseRiserAmount(amount: Float)
        @JvmStatic external fun nativeNoiseRiserAmount(): Float
        @JvmStatic external fun nativeSetTapeStopAmount(amount: Float)
        @JvmStatic external fun nativeTapeStopAmount(): Float
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
                "setMasterOutputGainDb" -> {
                    val db = (call.arguments as? Number)?.toFloat()
                    if (db == null) {
                        result.error("BAD_ARGS", "setMasterOutputGainDb expects number", null)
                    } else {
                        nativeSetMasterOutputGainDb(db)
                        result.success(null)
                    }
                }
                "masterOutputGainDb" -> result.success(nativeMasterOutputGainDb().toDouble())
                "setLimiterCeilingDb" -> {
                    val db = (call.arguments as? Number)?.toFloat()
                    if (db == null) {
                        result.error("BAD_ARGS", "setLimiterCeilingDb expects number", null)
                    } else {
                        nativeSetLimiterCeilingDb(db)
                        result.success(null)
                    }
                }
                "limiterCeilingDb" -> result.success(nativeLimiterCeilingDb().toDouble())
                "setTrackOutputGainDb" -> {
                    val args = call.arguments as? Map<*, *>
                    val trackId = (args?.get("trackId") as? Number)?.toInt()
                    val db = (args?.get("db") as? Number)?.toFloat()
                    if (trackId == null || db == null) {
                        result.error("BAD_ARGS", "setTrackOutputGainDb expects {trackId, db}", null)
                    } else {
                        nativeSetTrackOutputGainDb(trackId, db)
                        result.success(null)
                    }
                }
                "trackOutputGainDb" -> {
                    val id = (call.arguments as? Number)?.toInt()
                    if (id == null) result.error("BAD_ARGS", "trackOutputGainDb expects int", null)
                    else result.success(nativeTrackOutputGainDb(id).toDouble())
                }
                "setTrackDelaySendEnabled" -> {
                    val args = call.arguments as? Map<*, *>
                    val trackId = (args?.get("trackId") as? Number)?.toInt()
                    val enabled = args?.get("enabled") as? Boolean
                    if (trackId == null || enabled == null) {
                        result.error("BAD_ARGS", "setTrackDelaySendEnabled expects {trackId, enabled}", null)
                    } else {
                        nativeSetTrackDelaySendEnabled(trackId, enabled)
                        result.success(null)
                    }
                }
                "setTrackReverbSendEnabled" -> {
                    val args = call.arguments as? Map<*, *>
                    val trackId = (args?.get("trackId") as? Number)?.toInt()
                    val enabled = args?.get("enabled") as? Boolean
                    if (trackId == null || enabled == null) {
                        result.error("BAD_ARGS", "setTrackReverbSendEnabled expects {trackId, enabled}", null)
                    } else {
                        nativeSetTrackReverbSendEnabled(trackId, enabled)
                        result.success(null)
                    }
                }
                "setHighPassHz" -> {
                    val hz = (call.arguments as? Number)?.toFloat()
                    if (hz == null) result.error("BAD_ARGS", "setHighPassHz expects number", null)
                    else { nativeSetHighPassHz(hz); result.success(null) }
                }
                "highPassHz" -> result.success(nativeHighPassHz().toDouble())
                "setLowPassHz" -> {
                    val hz = (call.arguments as? Number)?.toFloat()
                    if (hz == null) result.error("BAD_ARGS", "setLowPassHz expects number", null)
                    else { nativeSetLowPassHz(hz); result.success(null) }
                }
                "lowPassHz" -> result.success(nativeLowPassHz().toDouble())
                "setEqLowDb" -> {
                    val db = (call.arguments as? Number)?.toFloat()
                    if (db == null) result.error("BAD_ARGS", "setEqLowDb expects number", null)
                    else { nativeSetEqLowDb(db); result.success(null) }
                }
                "eqLowDb" -> result.success(nativeEqLowDb().toDouble())
                "setEqMidDb" -> {
                    val db = (call.arguments as? Number)?.toFloat()
                    if (db == null) result.error("BAD_ARGS", "setEqMidDb expects number", null)
                    else { nativeSetEqMidDb(db); result.success(null) }
                }
                "eqMidDb" -> result.success(nativeEqMidDb().toDouble())
                "setEqHighDb" -> {
                    val db = (call.arguments as? Number)?.toFloat()
                    if (db == null) result.error("BAD_ARGS", "setEqHighDb expects number", null)
                    else { nativeSetEqHighDb(db); result.success(null) }
                }
                "eqHighDb" -> result.success(nativeEqHighDb().toDouble())
                "setCompressorAmount" -> {
                    val amount = (call.arguments as? Number)?.toFloat()
                    if (amount == null) result.error("BAD_ARGS", "setCompressorAmount expects number", null)
                    else { nativeSetCompressorAmount(amount); result.success(null) }
                }
                "compressorAmount" -> result.success(nativeCompressorAmount().toDouble())
                "setDistortionAmount" -> {
                    val amount = (call.arguments as? Number)?.toFloat()
                    if (amount == null) result.error("BAD_ARGS", "setDistortionAmount expects number", null)
                    else { nativeSetDistortionAmount(amount); result.success(null) }
                }
                "distortionAmount" -> result.success(nativeDistortionAmount().toDouble())
                "setSaturationAmount" -> {
                    val amount = (call.arguments as? Number)?.toFloat()
                    if (amount == null) result.error("BAD_ARGS", "setSaturationAmount expects number", null)
                    else { nativeSetSaturationAmount(amount); result.success(null) }
                }
                "saturationAmount" -> result.success(nativeSaturationAmount().toDouble())
                "setDelaySend" -> {
                    val amount = (call.arguments as? Number)?.toFloat()
                    if (amount == null) result.error("BAD_ARGS", "setDelaySend expects number", null)
                    else { nativeSetDelaySend(amount); result.success(null) }
                }
                "delaySend" -> result.success(nativeDelaySend().toDouble())
                "setDelayDivision" -> {
                    val division = (call.arguments as? Number)?.toInt()
                    if (division == null) result.error("BAD_ARGS", "setDelayDivision expects int", null)
                    else { nativeSetDelayDivision(division); result.success(null) }
                }
                "delayDivision" -> result.success(nativeDelayDivision())
                "setDelayFeel" -> {
                    val feel = (call.arguments as? Number)?.toInt()
                    if (feel == null) result.error("BAD_ARGS", "setDelayFeel expects int", null)
                    else { nativeSetDelayFeel(feel); result.success(null) }
                }
                "delayFeel" -> result.success(nativeDelayFeel())
                "setReverbSend" -> {
                    val amount = (call.arguments as? Number)?.toFloat()
                    if (amount == null) result.error("BAD_ARGS", "setReverbSend expects number", null)
                    else { nativeSetReverbSend(amount); result.success(null) }
                }
                "reverbSend" -> result.success(nativeReverbSend().toDouble())
                "setReverbRoomSize" -> {
                    val amount = (call.arguments as? Number)?.toFloat()
                    if (amount == null) result.error("BAD_ARGS", "setReverbRoomSize expects number", null)
                    else { nativeSetReverbRoomSize(amount); result.success(null) }
                }
                "reverbRoomSize" -> result.success(nativeReverbRoomSize().toDouble())
                "setDjFilterAmount" -> {
                    val amount = (call.arguments as? Number)?.toFloat()
                    if (amount == null) result.error("BAD_ARGS", "setDjFilterAmount expects number", null)
                    else { nativeSetDjFilterAmount(amount); result.success(null) }
                }
                "djFilterAmount" -> result.success(nativeDjFilterAmount().toDouble())
                "setDjFilterResonance" -> {
                    val amount = (call.arguments as? Number)?.toFloat()
                    if (amount == null) result.error("BAD_ARGS", "setDjFilterResonance expects number", null)
                    else { nativeSetDjFilterResonance(amount); result.success(null) }
                }
                "djFilterResonance" -> result.success(nativeDjFilterResonance().toDouble())
                "setBeatRepeatMix" -> {
                    val amount = (call.arguments as? Number)?.toFloat()
                    if (amount == null) result.error("BAD_ARGS", "setBeatRepeatMix expects number", null)
                    else { nativeSetBeatRepeatMix(amount); result.success(null) }
                }
                "beatRepeatMix" -> result.success(nativeBeatRepeatMix().toDouble())
                "setBeatRepeatDivision" -> {
                    val division = (call.arguments as? Number)?.toInt()
                    if (division == null) result.error("BAD_ARGS", "setBeatRepeatDivision expects int", null)
                    else { nativeSetBeatRepeatDivision(division); result.success(null) }
                }
                "beatRepeatDivision" -> result.success(nativeBeatRepeatDivision())
                "setTransGateAmount" -> {
                    val amount = (call.arguments as? Number)?.toFloat()
                    if (amount == null) result.error("BAD_ARGS", "setTransGateAmount expects number", null)
                    else { nativeSetTransGateAmount(amount); result.success(null) }
                }
                "transGateAmount" -> result.success(nativeTransGateAmount().toDouble())
                "setTransGateDivision" -> {
                    val division = (call.arguments as? Number)?.toInt()
                    if (division == null) result.error("BAD_ARGS", "setTransGateDivision expects int", null)
                    else { nativeSetTransGateDivision(division); result.success(null) }
                }
                "transGateDivision" -> result.success(nativeTransGateDivision())
                "setNoiseRiserAmount" -> {
                    val amount = (call.arguments as? Number)?.toFloat()
                    if (amount == null) result.error("BAD_ARGS", "setNoiseRiserAmount expects number", null)
                    else { nativeSetNoiseRiserAmount(amount); result.success(null) }
                }
                "noiseRiserAmount" -> result.success(nativeNoiseRiserAmount().toDouble())
                "setTapeStopAmount" -> {
                    val amount = (call.arguments as? Number)?.toFloat()
                    if (amount == null) result.error("BAD_ARGS", "setTapeStopAmount expects number", null)
                    else { nativeSetTapeStopAmount(amount); result.success(null) }
                }
                "tapeStopAmount" -> result.success(nativeTapeStopAmount().toDouble())
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
