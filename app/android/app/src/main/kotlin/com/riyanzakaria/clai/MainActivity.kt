package com.riyanzakaria.clai

import android.app.Activity
import android.app.PendingIntent
import android.bluetooth.BluetoothAdapter
import android.content.BroadcastReceiver
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.net.Uri
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.media.audiofx.AudioEffect
import android.media.audiofx.Equalizer
import android.media.audiofx.Visualizer
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.googlecode.tesseract.android.TessBaseAPI
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.InputStream
import java.util.Locale
import kotlin.math.log10
import kotlin.math.sqrt

class MainActivity : AudioServiceActivity() {

    // F2 Batch 2 'clai/audiofx': Equalizer + Visualizer per sesi audio pemain.
    // Equalizer menempel ke sesi pemain Clai sendiri (bukan mix global) agar
    // tidak mengubah audio aplikasi lain. Visualizer mengukur RMS bentuk
    // gelombang sesi itu untuk estimasi kenyaringan (normalisasi).
    private val equalizers = mutableMapOf<Int, Equalizer>()
    private val visualizers = mutableMapOf<Int, Visualizer>()
    // Galat terakhir pembuatan efek — TIDAK ditelan diam-diam lagi (F2 Batch
    // 2.1): diteruskan ke Dart agar tercatat di Log insiden perangkat.
    private var lastEqError: String? = null
    private var lastVisError: String? = null
    private var visSink: EventChannel.EventSink? = null
    private val visAccum = mutableMapOf<Int, Pair<Double, Long>>() // sesi -> (jumlah kuadrat, cacah)
    private val visEmitCount = mutableMapOf<Int, Int>()

    private fun eqFor(sessionId: Int): Equalizer? {
        return try {
            equalizers.getOrPut(sessionId) { Equalizer(0, sessionId) }
        } catch (e: Exception) {
            lastEqError = "${e.javaClass.simpleName}: ${e.message}"
            null
        }
    }

    private fun visListener(sessionId: Int) = object : Visualizer.OnDataCaptureListener {
        override fun onWaveFormDataCapture(
            visualizer: Visualizer, waveform: ByteArray, samplingRate: Int) {
            var sumSq = 0.0
            for (b in waveform) {
                val v = (b.toInt() and 0xFF) - 128
                val n = v / 128.0
                sumSq += n * n
            }
            val (acc, cnt) = visAccum[sessionId] ?: (0.0 to 0L)
            visAccum[sessionId] = (acc + sumSq) to (cnt + waveform.size)
            val n = (visEmitCount[sessionId] ?: 0) + 1
            visEmitCount[sessionId] = n
            if (n % 20 == 0) {
                val (a, c) = visAccum[sessionId] ?: (0.0 to 0L)
                if (c > 0) {
                    val rms = sqrt(a / c)
                    val db = if (rms <= 0.0) -96.0 else 20 * log10(rms)
                    try {
                        visSink?.success(mapOf("sessionId" to sessionId, "rmsDb" to db))
                    } catch (_: Exception) {
                    }
                }
            }
        }

        override fun onFftDataCapture(
            visualizer: Visualizer, fft: ByteArray, samplingRate: Int) {
        }
    }

    private fun visStart(sessionId: Int): Boolean {
        if (visualizers.containsKey(sessionId)) return true
        return try {
            val vis = Visualizer(sessionId)
            val sizes = Visualizer.getCaptureSizeRange()
            vis.captureSize = sizes[1]
            vis.setDataCaptureListener(
                visListener(sessionId), Visualizer.getMaxCaptureRate() / 2, true, false)
            vis.enabled = true
            visualizers[sessionId] = vis
            true
        } catch (e: Exception) {
            lastVisError = "${e.javaClass.simpleName}: ${e.message}"
            false
        }
    }

    private fun visStop(sessionId: Int) {
        try {
            visualizers.remove(sessionId)?.let {
                it.enabled = false
                it.release()
            }
        } catch (_: Exception) {
        }
        visAccum.remove(sessionId)
        visEmitCount.remove(sessionId)
    }

    private var installReceiver: BroadcastReceiver? = null
    private var installResult: MethodChannel.Result? = null

    // F2 Batch 2 'clai/tts': TTS sistem untuk pengumuman berkendara.
    private var tts: TextToSpeech? = null
    private var ttsReady = false

    private fun ttsSpeak(text: String) {
        try {
            if (tts == null) {
                tts = TextToSpeech(this) { status ->
                    ttsReady = status == TextToSpeech.SUCCESS
                    if (ttsReady) {
                        val id = Locale("id", "ID")
                        val r = tts?.setLanguage(id)
                        if (r == TextToSpeech.LANG_MISSING_DATA || r == TextToSpeech.LANG_NOT_SUPPORTED) {
                            tts?.language = Locale.getDefault()
                        }
                        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "clai-driving")
                    }
                }
            } else if (ttsReady) {
                tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "clai-driving")
            }
        } catch (_: Exception) {
        }
    }

    // F2 Batch 2 'clai/driving': lokasi GPS (LocationManager, tanpa Play
    // Services), daftar Bluetooth terpasang, status panggilan (API 31+).
    private var drivingSink: EventChannel.EventSink? = null
    private var locationManager: LocationManager? = null
    private var telephonyCallback: TelephonyCallback? = null
    private var callActive = false

    private val locationListener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            try {
                drivingSink?.success(mapOf(
                    "speedKmh" to (location.speed * 3.6f).toDouble(),
                    "accuracyM" to location.accuracy.toDouble(),
                    "callActive" to callActive
                ))
            } catch (_: Exception) {
            }
        }
    }

    private fun drivingStartLocation(): Boolean {
        return try {
            val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            locationManager = lm
            lm.requestLocationUpdates(
                LocationManager.GPS_PROVIDER, 2000L, 0f, locationListener)
            if (Build.VERSION.SDK_INT >= 31) {
                try {
                    val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
                    val cb = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                        override fun onCallStateChanged(state: Int) {
                            callActive = state != TelephonyManager.CALL_STATE_IDLE
                            try {
                                drivingSink?.success(mapOf("callActive" to callActive))
                            } catch (_: Exception) {
                            }
                        }
                    }
                    telephonyCallback = cb
                    tm.registerTelephonyCallback(mainExecutor, cb)
                } catch (_: Exception) {
                    // Tanpa izin baca status telepon: freeze-panggilan nonaktif,
                    // volume jalan normal (gagal-aman: tidak menebak).
                }
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun drivingStopLocation() {
        try {
            locationManager?.removeUpdates(locationListener)
        } catch (_: Exception) {
        }
        try {
            if (Build.VERSION.SDK_INT >= 31) {
                val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
                telephonyCallback?.let { tm.unregisterTelephonyCallback(it) }
            }
        } catch (_: Exception) {
        }
        telephonyCallback = null
    }

    // F2 Batch 2 'clai/voice': pengenal suara bawaan Android (tanpa LLM).
    private var voiceSink: EventChannel.EventSink? = null
    private var recognizer: SpeechRecognizer? = null

    private fun voiceListener() = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}

        override fun onError(error: Int) {
            try {
                voiceSink?.success(mapOf("error" to "kode $error"))
            } catch (_: Exception) {
            }
        }

        override fun onResults(results: Bundle?) {
            val list = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            val scores = results?.getFloatArray(SpeechRecognizer.CONFIDENCE_SCORES)
            val text = list?.firstOrNull()
            if (text != null) {
                try {
                    voiceSink?.success(mapOf(
                        "text" to text,
                        "isFinal" to true,
                        "confidence" to (scores?.firstOrNull()?.toDouble() ?: 1.0)
                    ))
                } catch (_: Exception) {
                }
            }
        }

        override fun onPartialResults(partialResults: Bundle?) {
            val list = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            val text = list?.firstOrNull()
            if (text != null) {
                try {
                    voiceSink?.success(mapOf("text" to text, "isFinal" to false))
                } catch (_: Exception) {
                }
            }
        }

        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    private fun voiceStart(lang: String): Boolean {
        return try {
            if (!SpeechRecognizer.isRecognitionAvailable(this)) return false
            recognizer?.destroy()
            val rec = SpeechRecognizer.createSpeechRecognizer(this)
            recognizer = rec
            rec.setRecognitionListener(voiceListener())
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE,
                    if (lang == "en") "en-US" else "id-ID")
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
            }
            rec.startListening(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun voiceStop() {
        try {
            recognizer?.stopListening()
        } catch (_: Exception) {
        }
    }

    // F2 Batch 2 'clai/share': tujuan berbagi Android (teks/gambar) + OCR.
    private var shareSink: EventChannel.EventSink? = null
    private var pendingShare: Map<String, String>? = null

    // Butir 6 F2.5: pemilih gambar sistem Android untuk pintu Tangkap di
    // layar Cari — tanpa izin penyimpanan luas (izin baca hanya untuk
    // berkas yang dipilih); hasil pilihan disalin ke cache privat lewat
    // penyalin yang sama seperti jalur berbagi gambar. Jalur klasik
    // startActivityForResult dipakai karena registerForActivityResult
    // tidak tersedia di classpath proyek ini (terbukti gagal kompilasi).
    private var pickImageResult: MethodChannel.Result? = null
    private val pickImageRequestCode = 0xC1A1

    @Deprecated("Jalur hasil klasik untuk pemilih gambar Tangkap")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickImageRequestCode) return
        val result = pickImageResult
        pickImageResult = null
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (uri == null) {
            result?.success(null)
        } else {
            result?.success(copySharedImageToCache(uri) ?: uri.toString())
        }
    }

    private fun extractShare(intent: Intent?): Map<String, String>? {
        if (intent == null || intent.action != Intent.ACTION_SEND) return null
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        if (!text.isNullOrEmpty()) return mapOf("kind" to "text", "value" to text)
        @Suppress("DEPRECATION")
        val stream = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        if (stream != null) {
            // Salin gambar ke cache privat SEKARANG, selagi izin URI dari
            // intent berbagi pasti sah: izin itu rapuh (bisa gugur sebelum
            // OCR sempat membuka URI-nya — terbukti di emulator: open
            // content:// gagal ENOENT walau URI benar). OCR kemudian
            // membaca berkas privat aplikasi sendiri, tanpa bergantung
            // pada izin pihak pemberi. Gagal menyalin → teruskan URI asli.
            val local = copySharedImageToCache(stream)
            return mapOf("kind" to "image", "value" to (local ?: stream.toString()))
        }
        return null
    }

    /// Salin gambar berbagi ke cache privat; kembalikan path mutlaknya
    /// atau null bila penyalinan tidak mungkin.
    private fun copySharedImageToCache(uri: Uri): String? {
        return try {
            val dir = File(cacheDir, "shared-capture").apply { mkdirs() }
            dir.listFiles()?.forEach { it.delete() }
            val ext = when (contentResolver.getType(uri)?.substringAfterLast('/')) {
                "png" -> "png"
                "webp" -> "webp"
                else -> "jpg"
            }
            val out = File(dir, "tangkapan.$ext")
            val input = contentResolver.openInputStream(uri) ?: return null
            input.use { inp -> out.outputStream().use { inp.copyTo(it) } }
            out.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    private fun deliverShare(share: Map<String, String>) {
        val sink = shareSink
        if (sink != null) {
            try {
                sink.success(share)
            } catch (_: Exception) {
                pendingShare = share
            }
        } else {
            pendingShare = share
        }
    }

    // F2 Batch 2.1 (cara ketiga): OCR Tesseract — model (traineddata) TIDAK
    // terbundel di APK; ia diunduh Dart (OcrModelController) ke penyimpanan
    // privat aplikasi dan jalur datapath-nya dikirim ke sini per panggilan.
    // Berkas model tidak ada → galat 'model-belum-ada' agar Dart menampilkan
    // keadaan jujur "model belum diunduh", bukan kegagalan misterius.
    private fun runOcr(uriString: String, dataPath: String, lang: String,
                       result: MethodChannel.Result) {
        val trained = File(dataPath, "tessdata/$lang.traineddata")
        if (!trained.isFile) {
            result.error("model-belum-ada",
                "Model pembaca teks belum diunduh.", null)
            return
        }
        Thread {
            var api: TessBaseAPI? = null
            try {
                val bmp = loadBitmapForOcr(uriString)
                    ?: throw IllegalStateException("Gambar tidak dapat dibaca.")
                api = TessBaseAPI()
                if (!api.init(dataPath, lang)) {
                    throw IllegalStateException("Mesin OCR gagal dimulai.")
                }
                api.setImage(bmp)
                // Fork adaptech: getter dipanggil sebagai metode &
                // pembersihan memakai recycle() (tidak ada end()).
                val text = api.getUTF8Text() ?: ""
                runOnUiThread { result.success(text) }
            } catch (e: Exception) {
                runOnUiThread { result.error("ocr-gagal", e.message, null) }
            } finally {
                try { api?.recycle() } catch (_: Exception) {}
            }
        }.start()
    }

    /// Muat bitmap dari URI konten/berkas, diperkecil agar sisi terpanjang
    /// ≤ 3000 px (cukup untuk daftar lagu; mencegah OOM pada foto besar).
    private fun loadBitmapForOcr(uriString: String): Bitmap? {
        val uri = Uri.parse(uriString)
        fun openStream(): InputStream? {
            // Utamakan ContentResolver: ia menghormati izin URI pada
            // berbagi content:// dari galeri/aplikasi lain (jalur normal
            // Tangkap). Berkas file:// yang tidak dapat dibuka resolver
            // dicoba sebagai berkas langsung.
            try {
                contentResolver.openInputStream(uri)?.let { return it }
            } catch (_: Exception) {}
            val p = uri.path ?: return null
            return FileInputStream(File(p))
        }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        openStream()?.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        val longest = maxOf(bounds.outWidth, bounds.outHeight)
        while (longest / sample > 3000) sample *= 2
        val opts = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        return openStream()?.use { BitmapFactory.decodeStream(it, null, opts) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractShare(intent)?.let { deliverShare(it) }
    }

    private fun registerInstallReceiver() {
        if (installReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
                when (status) {
                    PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                        @Suppress("DEPRECATION")
                        val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                        if (confirm != null) {
                            confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            try { startActivity(confirm) } catch (_: Exception) {}
                        }
                        // Hasil akhir menyusul pada siaran status berikutnya.
                    }
                    PackageInstaller.STATUS_SUCCESS -> {
                        installResult?.success(null); installResult = null
                    }
                    else -> {
                        val msg = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "status $status"
                        installResult?.error("gagal", msg, null); installResult = null
                    }
                }
            }
        }
        val filter = IntentFilter(INSTALL_STATUS_ACTION)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(receiver, filter)
        }
        installReceiver = receiver
    }

    private fun installApk(path: String, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.exists()) { result.error("gagal", "berkas tidak ditemukan: $path", null); return }
        if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
            result.error("izin", "izin pasang aplikasi tak dikenal belum diberikan", null); return
        }
        if (installResult != null) { result.error("gagal", "pemasangan lain sedang berjalan", null); return }
        registerInstallReceiver()
        installResult = result
        Thread {
            try {
                val installer = packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
                params.setAppPackageName(packageName)
                val sessionId = installer.createSession(params)
                val session = installer.openSession(sessionId)
                FileInputStream(file).use { input ->
                    session.openWrite("clai-update", 0, file.length()).use { out ->
                        input.copyTo(out)
                        session.fsync(out)
                    }
                }
                val intent = Intent(INSTALL_STATUS_ACTION).setPackage(packageName)
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                    if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
                val pending = PendingIntent.getBroadcast(this, sessionId, intent, flags)
                session.commit(pending.intentSender)
                session.close()
            } catch (e: Exception) {
                runOnUiThread { installResult?.error("gagal", e.message ?: "sesi pemasangan gagal", null); installResult = null }
            }
        }.start()
    }

    companion object {
        private const val INSTALL_STATUS_ACTION = "com.riyanzakaria.clai.INSTALL_STATUS"
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "clai/local_audio")
            .setMethodCallHandler { call, result ->
                if (call.method == "querySongs") {
                    Thread {
                        try { result.success(querySongs()) } catch (e: Exception) { result.error("query_failed", e.message, null) }
                    }.start()
                } else {
                    result.notImplemented()
                }
            }
        // Diagnostik Putar (v4.2): ekor logcat proses SENDIRI. just_audio hanya menulis
        // sebab natif ExoPlayer (mis. "TYPE_SOURCE: ... Response code: 403") ke logcat —
        // tidak pernah ke Dart. Android mengizinkan aplikasi membaca log prosesnya
        // sendiri tanpa izin khusus, jadi ini jendela resmi ke sebab itu.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "clai/diag_log")
            .setMethodCallHandler { call, result ->
                if (call.method == "readLogTail") {
                    Thread {
                        try { result.success(readLogTail()) } catch (e: Exception) { result.error("log_failed", e.message, null) }
                    }.start()
                } else {
                    result.notImplemented()
                }
            }
        // F2 'clai/sys': versi terpasang, ABI, jenis jaringan, pemasangan APK.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "clai/sys")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "appVersion" -> {
                        try {
                            val info = packageManager.getPackageInfo(packageName, 0)
                            val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong()
                            result.success(mapOf("versionName" to (info.versionName ?: "0.0.0"), "versionCode" to code))
                        } catch (e: Exception) { result.error("versi", e.message, null) }
                    }
                    "deviceAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
                    "networkType" -> {
                        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                        val caps = try { cm.getNetworkCapabilities(cm.activeNetwork) } catch (_: Exception) { null }
                        val type = when {
                            caps == null -> "none"
                            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
                            else -> "none"
                        }
                        result.success(type)
                    }
                    "canInstallPackages" -> result.success(
                        Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls())
                    "openInstallPermissionSettings" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= 26) {
                                val uri = android.net.Uri.parse("package:$packageName")
                                startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, uri)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            }
                            result.success(null)
                        } catch (e: Exception) { result.error("pengaturan", e.message, null) }
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) result.error("gagal", "path kosong", null) else installApk(path, result)
                    }
                    else -> result.notImplemented()
                }
            }
        // F2 Batch 2 'clai/audiofx': Equalizer + Visualizer (lihat blok field di atas).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "clai/audiofx")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "eqSupported" -> {
                        // F2 Batch 2.1 — AKAR CACAT build 2005: probe lama
                        // membuat Equalizer pada sesi 0 (mix global), yang
                        // ditolak Android modern/OEM (termasuk HyperOS)
                        // walau EQ pada sesi pemain yang sebenarnya bisa
                        // dibuat — UI pun menyatakan "tidak tersedia" secara
                        // keliru di HP riyan. Kini dukungan DIPUTUSKAN dari
                        // percobaan pembuatan pada sesi pemain yang hidup.
                        val sessionId = call.argument<Int>("sessionId")
                        if (sessionId == null) {
                            result.success(false)
                        } else {
                            result.success(eqFor(sessionId) != null)
                        }
                    }
                    "eqDiagnose" -> {
                        // Bukti terstruktur untuk Log insiden: deskriptor
                        // efek perangkat + hasil tiap jalur pembuatan.
                        val sessionId = call.argument<Int>("sessionId")
                        val out = mutableMapOf<String, Any?>()
                        try {
                            val descs = AudioEffect.queryEffects()
                            out["effects"] = descs?.map {
                                "${it.name}|type=${it.type}|impl=${it.implementor}"
                            } ?: emptyList<String>()
                        } catch (e: Exception) {
                            out["effectsError"] =
                                "${e.javaClass.simpleName}: ${e.message}"
                        }
                        out["session0"] = try {
                            val e = Equalizer(0, 0)
                            e.release()
                            "ok"
                        } catch (e: Exception) {
                            "${e.javaClass.simpleName}: ${e.message}"
                        }
                        if (sessionId != null) {
                            out["session"] = if (eqFor(sessionId) != null) "ok"
                                else (lastEqError ?: "gagal-tak-dikenal")
                            out["sessionId"] = sessionId
                        }
                        result.success(out)
                    }
                    "eqInfo" -> {
                        val sessionId = call.argument<Int>("sessionId")
                        if (sessionId == null) {
                            result.error("gagal", "sessionId kosong", null)
                        } else {
                            val eq = eqFor(sessionId)
                            if (eq == null) {
                                result.error("tak-tersedia", "Equalizer tidak tersedia untuk sesi ini", null)
                            } else {
                                val bands = eq.numberOfBands.toInt()
                                val freqs = (0 until bands).map { eq.getCenterFreq(it.toShort()) / 1000 }
                                val range = eq.bandLevelRange
                                val presets = (0 until eq.numberOfPresets).map { eq.getPresetName(it.toShort()) }
                                val levels = (0 until bands).map { eq.getBandLevel(it.toShort()).toInt() }
                                result.success(mapOf(
                                    "bandCount" to bands,
                                    "centerFreqHz" to freqs,
                                    "minLevel" to range[0].toInt(),
                                    "maxLevel" to range[1].toInt(),
                                    "presets" to presets,
                                    "currentPreset" to eq.currentPreset.toInt(),
                                    "bandLevels" to levels,
                                    "enabled" to eq.enabled
                                ))
                            }
                        }
                    }
                    "eqApply" -> {
                        val sessionId = call.argument<Int>("sessionId")
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val preset = call.argument<Int>("preset") ?: -1
                        @Suppress("UNCHECKED_CAST")
                        val levels = (call.argument<List<Int>>("bandLevels") ?: emptyList())
                        if (sessionId == null) {
                            result.error("gagal", "sessionId kosong", null)
                        } else {
                            val eq = eqFor(sessionId)
                            if (eq == null) {
                                result.error("tak-tersedia", "Equalizer tidak tersedia untuk sesi ini", null)
                            } else {
                                try {
                                    eq.enabled = enabled
                                    if (preset >= 0) {
                                        eq.usePreset(preset.toShort())
                                    } else {
                                        for (i in levels.indices) {
                                            if (i < eq.numberOfBands) {
                                                eq.setBandLevel(i.toShort(), levels[i].toShort())
                                            }
                                        }
                                    }
                                    result.success(null)
                                } catch (e: Exception) {
                                    result.error("gagal", e.message, null)
                                }
                            }
                        }
                    }
                    "visSupported" -> {
                        val sessionId = call.argument<Int>("sessionId")
                        if (sessionId == null) {
                            result.success(false)
                        } else {
                            try {
                                val v = Visualizer(sessionId)
                                v.release()
                                result.success(true)
                            } catch (_: Exception) {
                                result.success(false)
                            }
                        }
                    }
                    "visStart" -> {
                        val sessionId = call.argument<Int>("sessionId")
                        if (sessionId == null) {
                            result.error("gagal", "sessionId kosong", null)
                        } else if (visStart(sessionId)) {
                            result.success(true)
                        } else {
                            // Alasan asli diteruskan — Dart mencatatnya ke
                            // Log insiden (dulu: false senyap, normalisasi
                            // mati tanpa jejak).
                            result.error("vis-gagal",
                                lastVisError ?: "Visualizer gagal dimulai", null)
                        }
                    }
                    "visStop" -> {
                        val sessionId = call.argument<Int>("sessionId")
                        if (sessionId != null) visStop(sessionId)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "clai/audiofx_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) {
                    visSink = events
                }

                override fun onCancel(args: Any?) {
                    visSink = null
                }
            })
        // F2 Batch 2 'clai/tts' + 'clai/driving' (lihat blok field di atas).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "clai/tts")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "speak" -> {
                        val text = call.argument<String>("text")
                        if (text == null) result.error("gagal", "teks kosong", null)
                        else {
                            ttsSpeak(text)
                            result.success(null)
                        }
                    }
                    "stop" -> {
                        try { tts?.stop() } catch (_: Exception) {}
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "clai/driving")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bondedDevices" -> {
                        try {
                            val adapter = BluetoothAdapter.getDefaultAdapter()
                            val names = adapter?.bondedDevices
                                ?.mapNotNull { it.name }?.sorted() ?: emptyList()
                            result.success(names)
                        } catch (_: SecurityException) {
                            result.error("izin", "Izin Bluetooth belum diberikan", null)
                        } catch (e: Exception) {
                            result.error("gagal", e.message, null)
                        }
                    }
                    "startLocation" -> result.success(drivingStartLocation())
                    "stopLocation" -> {
                        drivingStopLocation()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "clai/driving_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) {
                    drivingSink = events
                }

                override fun onCancel(args: Any?) {
                    drivingSink = null
                }
            })
        // F2 Batch 2 'clai/voice' (lihat blok field di atas).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "clai/voice")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startListening" -> {
                        val lang = call.argument<String>("lang") ?: "id"
                        result.success(voiceStart(lang))
                    }
                    "stopListening" -> {
                        voiceStop()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "clai/voice_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) {
                    voiceSink = events
                }

                override fun onCancel(args: Any?) {
                    voiceSink = null
                }
            })
        // F2 Batch 2 'clai/share' (lihat blok field di atas).
        // Intent awal (cold start): ditangkap di sini karena configureFlutterEngine
        // berjalan sesudah intent tersedia pada activity.
        extractShare(intent)?.let { pendingShare = it }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "clai/share")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialShared" -> {
                        val s = pendingShare
                        pendingShare = null
                        result.success(s)
                    }
                    "pickCaptureImage" -> {
                        // Butir 6 F2.5: buka pemilih gambar sistem; hasil
                        // (atau null bila batal) tiba lewat onActivityResult.
                        if (pickImageResult != null) {
                            result.error("sibuk",
                                "Pemilih gambar sedang terbuka.", null)
                        } else {
                            pickImageResult = result
                            try {
                                val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                                    type = "image/*"
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                }
                                @Suppress("DEPRECATION")
                                startActivityForResult(intent, pickImageRequestCode)
                            } catch (e: Exception) {
                                pickImageResult = null
                                result.error("pemilih-gagal", e.message, null)
                            }
                        }
                    }
                    "ocrImage" -> {
                        val uriString = call.argument<String>("uri")
                        val dataPath = call.argument<String>("dataPath")
                        val lang = call.argument<String>("lang") ?: "eng"
                        if (uriString == null || dataPath == null) {
                            result.error("gagal", "uri/dataPath kosong", null)
                        } else {
                            runOcr(uriString, dataPath, lang, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "clai/share_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) {
                    shareSink = events
                    pendingShare?.let {
                        pendingShare = null
                        try {
                            events.success(it)
                        } catch (_: Exception) {
                        }
                    }
                }

                override fun onCancel(args: Any?) {
                    shareSink = null
                }
            })
    }

    private fun readLogTail(): String {
        fun run(args: List<String>): String {
            val p = ProcessBuilder(args).redirectErrorStream(true).start()
            val text = p.inputStream.bufferedReader().readText()
            p.waitFor()
            return text
        }
        return try {
            run(listOf("logcat", "-d", "-t", "500", "--pid", android.os.Process.myPid().toString()))
        } catch (e: Exception) {
            run(listOf("logcat", "-d", "-t", "500"))
        }
    }

    /// Pindai MediaStore sistem (sudah terindeks) — menggantikan plugin on_audio_query yang
    /// tidak memiliki namespace AGP dan tidak lagi terawat (penyebab gagal build, lihat catatan).
    private fun querySongs(): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        val uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION
        )
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        contentResolver.query(uri, projection, selection, null, "${MediaStore.Audio.Media.TITLE} ASC")?.use { c ->
            val idI = c.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val tI = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val aI = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val alI = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val dI = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            while (c.moveToNext()) {
                val id = c.getLong(idI)
                out.add(mapOf(
                    "id" to id.toString(),
                    "title" to (c.getString(tI) ?: "Tanpa judul"),
                    "artist" to c.getString(aI),
                    "album" to c.getString(alI),
                    "duration" to c.getLong(dI),
                    "uri" to ContentUris.withAppendedId(uri, id).toString()
                ))
            }
        }
        return out
    }
}
