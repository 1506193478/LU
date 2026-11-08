package com.lu.media;

import android.util.Base64;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;
import java.security.cert.X509Certificate;

/**
 * 原生 TCP 桥：为 Syncplay 协议（一起看）提供 socket 能力。
 * JS 端通过 Capacitor.Plugins.TcpSocket 调用，数据事件名 "luTcpData"。
 * 支持 STARTTLS 升级（Syncplay 协议的 TLS 协商）。
 */
@CapacitorPlugin(name = "TcpSocket")
public class TcpSocketPlugin extends Plugin {

  private Socket socket;
  private BufferedOutputStream out;
  private BufferedInputStream in;
  private final AtomicBoolean running = new AtomicBoolean(false);
  private Thread readerThread;

  @PluginMethod
  public void connect(PluginCall call) {
    String host = call.getString("host");
    int port = call.getInt("port", 8995);
    int timeout = call.getInt("timeout", 8000);
    if (host == null || host.isEmpty()) { call.reject("host required"); return; }
    if (socket != null) { closeQuietly(); }

    new Thread(() -> {
      try {
        Socket s = new Socket();
        s.connect(new InetSocketAddress(host, port), timeout);
        s.setTcpNoDelay(true);
        socket = s;
        out = new BufferedOutputStream(s.getOutputStream());
        in = new BufferedInputStream(s.getInputStream());
        running.set(true);
        startReading();
        JSObject ret = new JSObject();
        ret.put("ok", true);
        call.resolve(ret);
      } catch (Exception e) {
        call.reject("connect failed: " + e.getMessage());
      }
    }).start();
  }

  /** STARTTLS：把现有连接升级为 TLS（信任所有证书，与桌面 Syncplay 客户端行为一致的可选策略） */
  @PluginMethod
  public void startTls(PluginCall call) {
    try {
      Socket plain = socket;
      if (plain == null) { call.reject("not connected"); return; }
      TrustManager[] tm = new TrustManager[]{ new X509TrustManager() {
        public void checkClientTrusted(X509Certificate[] c, String a) {}
        public void checkServerTrusted(X509Certificate[] c, String a) {}
        public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
      }};
      SSLContext ctx = SSLContext.getInstance("TLS");
      ctx.init(null, tm, new java.security.SecureRandom());
      SSLSocket ssl = (SSLSocket) ctx.getSocketFactory().createSocket(plain, plain.getInetAddress().getHostAddress(), plain.getPort(), true);
      ssl.setUseClientMode(true);
      ssl.startHandshake();
      socket = ssl;
      out = new BufferedOutputStream(ssl.getOutputStream());
      in = new BufferedInputStream(ssl.getInputStream());
      call.resolve();
    } catch (Exception e) {
      call.reject("tls failed: " + e.getMessage());
    }
  }

  @PluginMethod
  public void write(PluginCall call) {
    String data = call.getString("data");
    if (data == null || out == null) { call.reject("not connected"); return; }
    try {
      synchronized (this) {
        out.write(data.getBytes(StandardCharsets.UTF_8));
        out.flush();
      }
      call.resolve();
    } catch (Exception e) {
      call.reject("write failed: " + e.getMessage());
    }
  }

  @PluginMethod
  public void disconnect(PluginCall call) {
    closeQuietly();
    if (call != null) call.resolve();
  }

  private void startReading() {
    readerThread = new Thread(() -> {
      StringBuilder pending = new StringBuilder();
      byte[] buf = new byte[8192];
      while (running.get()) {
        try {
          int n = in.read(buf);
          if (n < 0) break;
          String chunk = new String(buf, 0, n, StandardCharsets.UTF_8);
          pending.append(chunk);
          int idx;
          while ((idx = pending.indexOf("\n")) >= 0) {
            String line = pending.substring(0, idx).trim();
            pending.delete(0, idx + 1);
            if (!line.isEmpty()) emit(line);
          }
        } catch (Exception e) {
          break;
        }
      }
      running.set(false);
      emitEvent("luTcpClose", new JSObject());
    });
    readerThread.setDaemon(true);
    readerThread.start();
  }

  private void emit(String line) {
    JSObject obj = new JSObject();
    obj.put("data", line);
    emitEvent("luTcpData", obj);
  }

  private void emitEvent(String name, JSObject data) {
    notifyListeners(name, data);
  }

  private void closeQuietly() {
    running.set(false);
    try { if (out != null) out.close(); } catch (Exception ignored) {}
    try { if (in != null) in.close(); } catch (Exception ignored) {}
    try { if (socket != null) socket.close(); } catch (Exception ignored) {}
    socket = null; out = null; in = null;
  }

  @Override
  protected void handleOnDestroy() {
    closeQuietly();
    super.handleOnDestroy();
  }
}
