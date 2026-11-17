package com.example.uni360

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.speech.RecognizerIntent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var speechResult: MethodChannel.Result? = null
    private val speechRequest = 360

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "uni360/speech")
            .setMethodCallHandler { call, result ->
                if (call.method != "listen") {
                    result.notImplemented()
                } else if (speechResult != null) {
                    result.error("busy", "Voice input is already open.", null)
                } else {
                    speechResult = result
                    val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                        .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                        .putExtra(RecognizerIntent.EXTRA_PROMPT, "Describe the facility fault")
                        .putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                    try {
                        startActivityForResult(intent, speechRequest)
                    } catch (_: ActivityNotFoundException) {
                        speechResult = null
                        result.error("unavailable", "This phone has no speech recognizer.", null)
                    }
                }
            }
    }

    @Deprecated("Required for the system speech recognition activity result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != speechRequest) return
        val text = if (resultCode == Activity.RESULT_OK)
            data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
        else null
        speechResult?.success(text)
        speechResult = null
    }
}
