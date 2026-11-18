# LU 一起看 · 公网中继

局域网（Bonjour / IP 直连）只能同一个 Wi-Fi。要跨网络同步播放，双方各连一台中继，
由中继把消息转发给同一房间的其他人。中继**只转发，不落库、不录制**。

## 跑起来

```bash
# 本机（需要 Deno 1.4x+）
deno run --allow-net --allow-env lu-sync-relay.ts

# 指定端口
PORT=9000 deno run --allow-net --allow-env lu-sync-relay.ts
```

部署到 Deno Deploy（免费，自带 HTTPS，手机可以直接连 `wss://`）：

```bash
deno deploy --project lu-sync --prod
# 拿到 https://lu-sync.xxxx.deno.dev
```

任何支持 WebSocket 的宿主都行（Fly.io / Railway / 自己的 VPS + Caddy 反代）。
如果放在自己的 VPS 上、前面是 Nginx，记得转发 Upgrade 头：

```nginx
location / {
    proxy_pass http://127.0.0.1:8787;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 3600s;
}
```

## 在 App 里填

「一起看」页 → 跨网络 → 中继地址填 `wss://lu-sync.xxxx.deno.dev`（会自动补 `wss://`，
也可以只填 `1.2.3.4:8787`）。地址存在本地设置 `lu.sync.relay`，下次不用再填。

## 协议

文本帧，JSON。`create` / `join` 是控制消息，其余原样转发。

| 方向 | 消息 | 说明 |
|---|---|---|
| → | `{"type":"create","name":"小明"}` | 房主建房 |
| ← | `{"type":"created","code":"7K3QP"}` | 5 位房间码（排除易混字符） |
| → | `{"type":"join","code":"7K3QP"}` | 观众加入 |
| ← | `{"type":"joined","code":"7K3QP","members":2}` | 加入成功 |
| ← | `{"type":"error","text":"房间不存在或已关闭"}` | 加入失败 |
| ↔ | `state` / `play` / `pause` / `seek` / `episode` / `chat` | 业务消息 |

转发规则：

- 房主 → 所有观众
- 观众的 `play/pause/seek/episode` → 只给房主（房主应用到本地再广播 `state`）
- 观众的 `chat` → 房主 + 其他观众

环境变量：`PORT`（默认 8787）、`MAX_GUESTS`（默认 16）。
