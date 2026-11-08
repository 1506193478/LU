/* ============ LU · Syncplay 协议客户端（一起看真实数据层） ============ */
/* 与 LU Flutter 版 lib/services/player/syncplay_client.dart 同一套协议实现：
   换行分隔 JSON；Hello/State/Set/Chat/StartTLS；ignoringOnTheFly + ping/latency。
   传输层：Capacitor.Plugins.TcpSocket（原生 TCP 桥，Android/iOS 均已实现）。 */
(function(){
'use strict';

const VERSION = '1.7.0';

function now(){ return Date.now()/1000; }

class SyncplayClient {
  constructor({ host, port = 8995, useTls = false, username, room }){
    this.host = host; this.port = port; this.useTls = !!useTls;
    this.username = username || 'LU';
    this.room = room;
    this.connected = false;
    this.position = 0; this.paused = true;
    this.duration = 0; this.fileName = null; this.fileSize = 0;
    this.users = new Map();          // name -> {room, file, ready}
    this.chatLog = [];               // [{user, msg, t}]
    this.serverRtt = 0; this.clientRtt = 0; this.avgRtt = 0;
    this._clientIgn = 0; this._serverIgn = 0;
    this._lastLatencyCalc = null;
    this._buf = '';
    this._listeners = { message:[], chat:[], users:[], position:[], state:[], close:[] };
    this._stateTimer = null;
  }

  on(ev, fn){ (this._listeners[ev]||[]).push(fn); return ()=>{ this._listeners[ev] = (this._listeners[ev]||[]).filter(f=>f!==fn); }; }
  _emit(ev, data){ (this._listeners[ev]||[]).forEach(f=>{ try{ f(data); }catch(e){} }); }

  _plugin(){ try{ return (window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.TcpSocket) || null; }catch(e){ return null; } }

  async connect(){
    const T = this._plugin();
    if(!T) throw new Error('TcpSocket 原生桥不可用（仅原生 App 内可用）');
    await T.connect({ host: this.host, port: this.port, timeout: 8000 });
    this._dataHandler = (d)=> this._feed(d && d.data || '');
    this._closeHandler = ()=>{ this.connected=false; this._stopStateLoop(); this._emit('close'); };
    T.addListener && T.addListener('luTcpData', this._dataHandler);
    T.addListener && T.addListener('luTcpClose', this._closeHandler);
    this.connected = true;
    if(this.useTls){
      this._send({ 'StartTLS': 'send' });
      await new Promise((res)=> setTimeout(res, 300));   // 等服务端 startTLS 确认
      await T.startTls({});
    }
    await this._send({ 'Hello': {
      username: this.username,
      room: { name: this.room },
      version: VERSION,
      features: { sharedPlaylists:true, chat:true, featureList:true, readiness:true, managedRooms:false }
    }});
    this._startStateLoop();
  }

  disconnect(){
    this.connected = false;
    this._stopStateLoop();
    const T = this._plugin();
    if(T){ try{ this._dataHandler && T.removeListener && T.removeListener('luTcpData', this._dataHandler); }catch(e){}
           try{ this._closeHandler && T.removeListener && T.removeListener('luTcpClose', this._closeHandler); }catch(e){}
           try{ T.disconnect({}); }catch(e){} }
    this._emit('close');
  }

  _send(obj){
    const T = this._plugin(); if(!T || !this.connected) return;
    T.write({ data: JSON.stringify(obj) + '\n' }).catch(()=>{});
  }

  _feed(chunk){
    this._buf += chunk;
    let idx;
    while((idx = this._buf.indexOf('\n')) >= 0){
      const line = this._buf.slice(0, idx).trim();
      this._buf = this._buf.slice(idx+1);
      if(!line) continue;
      try{ this._handle(JSON.parse(line)); }catch(e){}
    }
  }

  _handle(msg){
    if(msg.StartTLS !== undefined || msg.startTLS !== undefined) return;
    if(msg.Hello){
      // 服务端确认加入
      this._emit('message', { type:'hello' });
      this._sendFileState();
      return;
    }
    if(msg.Set){ this._handleSet(msg.Set); return; }
    if(msg.State){ this._handleState(msg.State); return; }
    if(msg.Chat !== undefined){
      const user = msg.Chat && msg.Chat.username || msg.Chat.user || '?';
      const text = msg.Chat && msg.Chat.message || String(msg.Chat);
      const entry = { user, msg: text, t: Date.now() };
      this.chatLog.push(entry);
      if(this.chatLog.length>200) this.chatLog.shift();
      this._emit('chat', entry);
      return;
    }
    if(msg.List){ this._handleList(msg.List); return; }
    if(msg.FileChanged) this._emit('message', { type:'fileChanged', by: msg.FileChanged.set_by || msg.FileChanged['set_by'] });
    this._emit('message', { type:'other', raw: msg });
  }

  _handleSet(set){
    // 用户加入/离开房间
    Object.keys(set).forEach(k=>{
      if(k==='user' || (set[k] && set[k].room && set[k].event)){
        const name = set['user'] ? Object.keys(set['user'])[0] : k;
        const info = set['user'] ? set['user'][name] : set[k];
        const roomName = info && info.room && (info.room.name || info.room);
        const ev = info && info.event || {};
        if(ev.joined !== undefined || ev.joined){
          this.users.set(name, { room: roomName, file: null, ready:false });
          this._emit('message', { type:'joined', user:name, room:roomName });
        } else if(ev.left){
          this.users.delete(name);
          this._emit('message', { type:'left', user:name });
        } else if(roomName !== undefined && name){
          const u = this.users.get(name) || {};
          u.room = roomName && roomName.name !== undefined ? roomName.name : roomName;
          this.users.set(name, u);
        }
        return;
      }
      if(k==='room' && set[k] && set[k].event){ return; }
      if(k==='empty' || k==='ready'){ return; }
      // 文件设置（成员当前文件）
      const v = set[k];
      if(v && typeof v==='object' && (v.file || v.name)){
        const u = this.users.get(k) || { room:this.room, file:null, ready:false };
        u.file = v.file || v.name;
        u.duration = v.duration || 0;
        this.users.set(k, u);
        this._emit('message', { type:'file', user:k, file:u.file });
      }
    });
    this._emit('users', this.userList());
  }

  _handleList(list){
    // {"user": [ {"name":..,"room":{"name":..},"file":{...},"ready":bool} ]}
    const arr = list && (list.user || list) || [];
    if(Array.isArray(arr)){
      this.users.clear();
      arr.forEach(u=>{
        const name = u.name || u.username;
        if(!name) return;
        this.users.set(name, {
          room: u.room && (u.room.name || u.room),
          file: u.file && (u.file.name || null),
          duration: u.file && u.file.duration || 0,
          ready: !!u.ready
        });
      });
      this._emit('users', this.userList());
    }
  }

  _handleState(st){
    // ignoringOnTheFly ack
    const iotf = st.ignoringOnTheFly;
    if(iotf){
      if(iotf.server !== undefined && iotf.server !== null){
        this._serverIgn = iotf.server;                       // 收到 server ack
        this._send({ 'State': { 'ignoringOnTheFly': { 'server': this._serverIgn } } });
      }
      if(iotf.client !== undefined && iotf.client !== null){
        this._clientIgn = 0;                                  // client ack：恢复本地接收
      }
    }
    const ping = st.ping || {};
    if(ping.latencyCalculation !== undefined){
      this.serverRtt = now() - ping.latencyCalculation;
      this.avgRtt = this.avgRtt ? this.avgRtt*0.85 + this.serverRtt*0.15 : this.serverRtt;
    }
    this._lastLatencyCalc = ping.clientLatencyCalculation !== undefined ? ping.clientLatencyCalculation : null;
    const ps = st.playstate || {};
    if(this._clientIgn > 0) return;                           // 正在忽略（本端 seek 中）
    const changed = {};
    if(ps.position !== undefined && ps.position !== null){
      const prev = this.position;
      this.position = ps.position;
      if(Math.abs(prev - ps.position) > 0.05) this._emit('position', ps.position);
      changed.position = ps.position;
    }
    if(ps.paused !== undefined && ps.paused !== null){
      this.paused = ps.paused;
      changed.paused = ps.paused;
    }
    if(ps.doSeek) changed.doSeek = true;
    if(ps.setBy) changed.setBy = ps.setBy;
    if(Object.keys(changed).length) this._emit('state', changed);
  }

  _startStateLoop(){
    this._stopStateLoop();
    this._stateTimer = setInterval(()=>{
      if(!this.connected) return;
      this._sendState();
    }, 1000);
  }
  _stopStateLoop(){ if(this._stateTimer){ clearInterval(this._stateTimer); this._stateTimer=null; } }

  _sendState(){
    const st = {
      ping: {
        clientRtt: this.clientRtt,
        clientLatencyCalculation: now()
      },
      playstate: {
        position: this.position,
        paused: this.paused,
        doSeek: false
      }
    };
    if(this._lastLatencyCalc !== null) st.ping.latencyCalculation = this._lastLatencyCalc;
    this._send({ 'State': st });
  }

  /* 本端播放器同步进协议 */
  setLocalState(position, paused, fromSeek){
    this.position = position; this.paused = paused;
    if(fromSeek){
      this._clientIgn += 1;
      const st = { ping:{ clientRtt:this.clientRtt, clientLatencyCalculation:now() },
                   playstate:{ position, paused, doSeek:true } };
      this._send({ 'State': { 'ignoringOnTheFly': { 'client': this._clientIgn }, ...st } });
    }
  }

  sendChat(text){ this._send({ 'Chat': text }); }

  setFileState(name, durationSec, size){
    this.fileName = name; this.duration = durationSec; this.fileSize = size || 0;
    this._sendFileState();
  }
  _sendFileState(){
    if(!this.fileName) return;
    this._send({ 'Set': {
      file: { name: this.fileName, duration: this.duration, size: this.fileSize },
      user: { [this.username]: { room: { name: this.room } } }
    }});
  }

  userList(){
    const arr = [];
    this.users.forEach((v,k)=> arr.push({ name:k, room:v.room, file:v.file, ready:v.ready }));
    if(!arr.find(u=>u.name===this.username)) arr.unshift({ name:this.username, room:this.room, file:this.fileName, ready:true, me:true });
    return arr;
  }
}

/* 默认服务器（与桌面 Syncplay 客户端常用一致） */
const DEFAULT_SERVERS = [
  { name:'Syncplay 官方', host:'syncplay.pl', port:8995, tls:false },
  { name:'Syncplay 官方 TLS', host:'syncplay.pl', port:8996, tls:true },
  { name:'自定义', host:'', port:8995, tls:false }
];

window.Syncplay = { SyncplayClient, DEFAULT_SERVERS, VERSION };
})();
