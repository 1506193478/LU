package com.predidit.XL

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.libtorrent4j.Priority
import org.libtorrent4j.SessionManager
import org.libtorrent4j.TorrentFlags
import org.libtorrent4j.TorrentHandle
import org.libtorrent4j.TorrentInfo
import org.libtorrent4j.alerts.AddTorrentAlert
import org.libtorrent4j.alerts.Alert
import org.libtorrent4j.alerts.MetadataFailedAlert
import org.libtorrent4j.alerts.MetadataReceivedAlert
import org.libtorrent4j.alerts.TorrentErrorAlert
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * 磁力/种子播放引擎（libtorrent4j）。
 *
 * 与 Dart 侧（lib/services/torrent/lu_torrent.dart）的协议：
 *   MethodChannel `lu/torrent`：
 *     - start(magnet, saveDir)   添加磁力/.torrent 并开跑
 *     - fileInfo()               元数据就绪后的文件信息（名/大小/分片）
 *     - status()                 progress / speed / peers
 *     - prioritize(start,end)    把字节区间提升为最优先（供流前调用）
 *     - isReady(start,end)       字节区间所在分片是否全部落盘
 *     - stop()                   停掉会话并清理
 *   EventChannel `lu/torrent/events`：
 *     - metadata / metadata_failed / added / error
 */
class TorrentEngine(context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val METHOD_CHANNEL = "lu/torrent"
        const val EVENT_CHANNEL = "lu/torrent/events"
        private const val METADATA_TIMEOUT_MS = 120_000L
    }

    private val appContext = context.applicationContext
    private var session: SessionManager? = null
    private val handle = AtomicReference<TorrentHandle?>(null)
    private val gotMetadata = AtomicBoolean(false)
    private val failed = AtomicReference<String?>(null)
    private var eventSink: EventChannel.EventSink? = null

    // 主文件（最大的那个视频文件）信息。
    private var mainFileIndex = -1
    private var mainFileOffset = 0L
    private var mainFileSize = 0L
    private var mainFilePath: String? = null
    private var pieceLength = 0
    private var numPieces = 0
    private var fileName = ""

    @Volatile
    private var running = false

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler(this)
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                }

                override fun onCancel(args: Any?) {
                    eventSink = null
                }
            }
        )
    }

    fun dispose() {
        stopSession()
    }

    private fun emit(event: String, args: Map<String, Any?> = emptyMap()) {
        val sink = eventSink ?: return
        val payload = HashMap<String, Any?>(args)
        payload["event"] = event
        sink.success(payload)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val source = call.argument<String>("magnet") ?: ""
                val saveDir = call.argument<String>("saveDir") ?: ""
                try {
                    startSession(source, saveDir)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("START_FAILED", e.message ?: e.toString(), null)
                }
            }
            "fileInfo" -> {
                result.success(
                    if (gotMetadata.get()) mapOf(
                        "fileName" to fileName,
                        "fileSize" to mainFileSize,
                        "fileOffset" to mainFileOffset,
                        "pieceLength" to pieceLength,
                        "numPieces" to numPieces,
                        "path" to (mainFilePath ?: ""),
                    ) else null
                )
            }
            "status" -> {
                val h = handle.get()
                if (h == null || !gotMetadata.get()) {
                    result.success(
                        mapOf("progress" to 0.0, "speed" to 0, "peers" to 0, "state" to "fetching")
                    )
                    return
                }
                try {
                    val st = h.status()
                    result.success(
                        mapOf(
                            "progress" to st.progress().toDouble(),
                            "speed" to st.downloadPayloadRate(),
                            "peers" to st.numPeers(),
                            "state" to if (st.isFinished()) "completed" else "downloading",
                        )
                    )
                } catch (e: Exception) {
                    result.success(
                        mapOf("progress" to 0.0, "speed" to 0, "peers" to 0, "state" to "unknown")
                    )
                }
            }
            "prioritize" -> {
                val start = call.argument<Number>("start")?.toLong() ?: 0L
                val end = call.argument<Number>("end")?.toLong() ?: 0L
                result.success(prioritizeRange(start, end))
            }
            "isReady" -> {
                val start = call.argument<Number>("start")?.toLong() ?: 0L
                val end = call.argument<Number>("end")?.toLong() ?: 0L
                result.success(isRangeReady(start, end))
            }
            "stop" -> {
                stopSession()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun startSession(source: String, saveDirPath: String) {
        if (running) stopSession()
        gotMetadata.set(false)
        failed.set(null)
        handle.set(null)
        mainFileIndex = -1
        mainFileSize = 0
        fileName = ""

        val dir = File(saveDirPath).apply { mkdirs() }
        val sm = SessionManager()
        session = sm
        running = true

        sm.addListener(object : org.libtorrent4j.AlertListener {
            override fun types(): IntArray? = null // 收全部，按类型分发。

            override fun alert(alert: Alert<*>) {
                when (alert) {
                    is MetadataReceivedAlert -> {
                        val h = alert.handle()
                        if (h != null) onMetadata(h)
                        emit("metadata", mapOf("name" to fileName))
                    }
                    is MetadataFailedAlert -> {
                        failed.compareAndSet(null, "种子元数据获取失败（无可用 peer）")
                        emit("metadata_failed")
                    }
                    is AddTorrentAlert -> {
                        emit("added")
                    }
                    is TorrentErrorAlert -> {
                        failed.compareAndSet(
                            null, "种子错误：${alert.message()}"
                        )
                        emit("error", mapOf("message" to alert.message()))
                    }
                    else -> {}
                }
            }
        })

        sm.start()

        val magnetFlags = TorrentFlags.SEQUENTIAL_DOWNLOAD
        if (source.trim().lowercase().startsWith("magnet:")) {
            sm.download(source.trim(), dir, magnetFlags)
        } else if (source.trim().lowercase().startsWith("http")) {
            // .torrent 地址：下载字节再解析（在子线程做，避免阻塞）。
            val bytes = fetchTorrentFile(source.trim())
            val ti = TorrentInfo(bytes)
            sm.download(ti, dir)
            val h = sm.find(ti.infoHash())
            if (h != null) {
                h.setFlags(TorrentFlags.SEQUENTIAL_DOWNLOAD)
            }
        } else {
            throw IllegalArgumentException("不是磁力链接或种子地址")
        }

        // 元数据在 listener 里就绪；这里不等（Dart 侧轮询 fileInfo/status）。
    }

    private fun fetchTorrentFile(url: String): ByteArray {
        val conn = java.net.URL(url).openConnection() as java.net.HttpURLConnection
        conn.connectTimeout = 15000
        conn.readTimeout = 20000
        conn.setRequestProperty(
            "User-Agent",
            "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124 Mobile Safari/537.36"
        )
        conn.instanceFollowRedirects = true
        try {
            conn.inputStream.use { input ->
                return input.readBytes()
            }
        } finally {
            conn.disconnect()
        }
    }

    private fun onMetadata(h: TorrentHandle) {
        if (!gotMetadata.compareAndSet(false, true)) return
        handle.set(h)
        val ti = h.torrentFile() ?: return
        val files = ti.files()
        var best = 0
        var bestSize = 0L
        for (i in 0 until files.numFiles()) {
            val s = files.fileSize(i)
            if (s > bestSize) {
                bestSize = s
                best = i
            }
        }
        mainFileIndex = best
        mainFileOffset = files.fileOffset(best)
        mainFileSize = bestSize
        pieceLength = ti.pieceLength()
        numPieces = ti.numPieces()
        fileName = files.fileName(best) ?: "video"
        mainFilePath = File(h.savePath(), files.filePath(best)).absolutePath

        // 只下主文件，其余 IGNORE；主文件交给顺序下载策略。
        for (i in 0 until files.numFiles()) {
            try {
                h.filePriority(i, if (i == best) Priority.DEFAULT else Priority.IGNORE)
            } catch (_: Exception) {
            }
        }
        try {
            val startPiece = (mainFileOffset / pieceLength).toInt()
            val endPiece =
                ((mainFileOffset + mainFileSize - 1) / pieceLength).toInt().coerceAtLeast(startPiece)
            h.setSequentialRange(startPiece, endPiece)
        } catch (_: Exception) {
        }
    }

    private fun prioritizeRange(startByte: Long, endByte: Long): Boolean {
        val h = handle.get() ?: return false
        if (pieceLength <= 0) return false
        val absStart = mainFileOffset + startByte.coerceIn(0, mainFileSize)
        val absEnd = mainFileOffset + endByte.coerceIn(0, mainFileSize)
        val p0 = (absStart / pieceLength).toInt()
        val p1 = (absEnd / pieceLength).toInt().coerceAtLeast(p0)
        try {
            for (p in p0..p1.coerceAtMost(numPieces - 1)) {
                if (!h.havePiece(p)) {
                    h.setPieceDeadline(p, 5_000)
                }
            }
            return true
        } catch (_: Exception) {
            return false
        }
    }

    private fun isRangeReady(startByte: Long, endByte: Long): Boolean {
        val h = handle.get() ?: return false
        if (pieceLength <= 0) return false
        val absStart = mainFileOffset + startByte.coerceIn(0, mainFileSize)
        val absEnd = mainFileOffset + endByte.coerceIn(0, mainFileSize)
        val p0 = (absStart / pieceLength).toInt()
        val p1 = (absEnd / pieceLength).toInt().coerceAtLeast(p0)
        for (p in p0..p1.coerceAtMost(numPieces - 1)) {
            if (!h.havePiece(p)) return false
        }
        return true
    }

    private fun stopSession() {
        running = false
        val sm = session
        session = null
        handle.set(null)
        if (sm != null) {
            try {
                sm.stop()
            } catch (_: Exception) {
            }
        }
    }
}

