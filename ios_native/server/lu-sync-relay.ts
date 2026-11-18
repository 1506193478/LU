// LU「一起看」公网中继
//
// 只做一件事：把房间里的消息转发给同一个房间的其他人。不落库、不录制、不转码。
// 零依赖，Deno 1.4x+ 直接跑：
//
//   deno run --allow-net --allow-env lu-sync-relay.ts
//   # 或部署：deno deploy --project lu-sync
//
// 协议（文本帧，JSON）：
//   → {"type":"create","name":"小明"}          ← {"type":"created","code":"7K3QP"}
//   → {"type":"join","code":"7K3QP","name":"小红"} ← {"type":"joined","code":"7K3QP","members":2}
//   之后 state / play / pause / seek / episode / chat 原样转发。
//   房主 → 所有观众；观众的操作 → 房主；观众的 chat → 房主和其他观众。
//
// 环境变量：PORT（默认 8787）、MAX_GUESTS（默认 16）

type Room = {
  code: string;
  host: WebSocket;
  guests: Set<WebSocket>;
  createdAt: number;
};

const rooms = new Map<string, Room>();
const MAX_GUESTS = Number(Deno.env.get("MAX_GUESTS") ?? "16");
const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function makeCode(): string {
  for (let attempt = 0; attempt < 50; attempt++) {
    let code = "";
    for (let i = 0; i < 5; i++) {
      code += ALPHABET[Math.floor(Math.random() * ALPHABET.length)];
    }
    if (!rooms.has(code)) return code;
  }
  return Math.random().toString(36).slice(2, 7).toUpperCase();
}

function send(socket: WebSocket, payload: unknown) {
  if (socket.readyState !== WebSocket.OPEN) return;
  try {
    socket.send(JSON.stringify(payload));
  } catch {
    // 对端刚断开，忽略
  }
}

function memberCount(room: Room): number {
  return 1 + room.guests.size;
}

function notifyMembers(room: Room) {
  const message = { type: "peer", members: memberCount(room) };
  send(room.host, message);
  for (const guest of room.guests) send(guest, message);
}

function closeRoom(room: Room, reason: string) {
  for (const guest of room.guests) {
    send(guest, { type: "error", text: reason });
    try {
      guest.close(1000, "room closed");
    } catch {
      // ignore
    }
  }
  rooms.delete(room.code);
}

Deno.serve(
  { port: Number(Deno.env.get("PORT") ?? "8787") },
  (request) => {
    const upgrade = (request.headers.get("upgrade") ?? "").toLowerCase();
    if (upgrade !== "websocket") {
      return new Response(
        `LU sync relay running · rooms=${rooms.size}\n`,
        { headers: { "content-type": "text/plain; charset=utf-8" } },
      );
    }

    const { socket, response } = Deno.upgradeWebSocket(request);
    let room: Room | null = null;
    let isHost = false;

    socket.onmessage = (event) => {
      let message: Record<string, unknown>;
      try {
        message = JSON.parse(String(event.data));
      } catch {
        return;
      }
      const type = String(message.type ?? "");

      if (type === "create") {
        if (room) rooms.delete(room.code);
        const created: Room = {
          code: makeCode(),
          host: socket,
          guests: new Set(),
          createdAt: Date.now(),
        };
        rooms.set(created.code, created);
        room = created;
        isHost = true;
        send(socket, { type: "created", code: created.code, members: 1 });
        console.log(`[create] ${created.code} (rooms=${rooms.size})`);
        return;
      }

      if (type === "join") {
        const code = String(message.code ?? "").toUpperCase();
        const target = rooms.get(code);
        if (!target) {
          send(socket, { type: "error", text: "房间不存在或已关闭" });
          return;
        }
        if (target.guests.size >= MAX_GUESTS) {
          send(socket, { type: "error", text: "房间人数已满" });
          return;
        }
        target.guests.add(socket);
        room = target;
        isHost = false;
        send(socket, {
          type: "joined",
          code: target.code,
          members: memberCount(target),
        });
        notifyMembers(target);
        console.log(`[join] ${target.code} members=${memberCount(target)}`);
        return;
      }

      if (type === "ping") {
        send(socket, { type: "pong", timestamp: Date.now() });
        return;
      }

      if (!room) return;

      // 业务消息：原样转发
      if (isHost) {
        for (const guest of room.guests) send(guest, message);
      } else if (type === "chat") {
        // 聊天广播：房主 + 其他观众
        send(room.host, message);
        for (const guest of room.guests) {
          if (guest !== socket) send(guest, message);
        }
      } else {
        send(room.host, message);
      }
    };

    socket.onclose = () => {
      if (!room) return;
      if (isHost) {
        console.log(`[close-host] ${room.code}`);
        closeRoom(room, "房主已离开");
      } else {
        room.guests.delete(socket);
        if (room.guests.size === 0 && room.host.readyState !== WebSocket.OPEN) {
          rooms.delete(room.code);
        } else {
          notifyMembers(room);
        }
      }
      room = null;
    };

    socket.onerror = () => {
      // onclose 会跟着触发，这里不重复处理
    };

    return response;
  },
);

// 每 10 分钟清一次「房主早就不在了」的空房间
setInterval(() => {
  for (const [code, room] of rooms) {
    if (room.host.readyState !== WebSocket.OPEN) {
      closeRoom(room, "房主已离开");
      console.log(`[reap] ${code}`);
    }
  }
}, 10 * 60 * 1000);
