/* ============ LU · Emby REST API 客户端（真实数据层） ============ */
(function(){
'use strict';

const LS = {
  get(k, def){ try{ const v = localStorage.getItem(k); return v ? JSON.parse(v) : def; }catch(e){ return def; } },
  set(k, v){ try{ localStorage.setItem(k, JSON.stringify(v)); }catch(e){} }
};

const DEVICE_ID = (()=>{ let d = LS.get('lu.deviceId', null);
  if(!d){ d = 'lu-' + Math.random().toString(36).slice(2, 10); LS.set('lu.deviceId', d); }
  return d; })();

function authHeader(){
  return 'MediaBrowser Client="LU", Device="LU", DeviceId="' + DEVICE_ID + '", Version="1.1.0"';
}

const COLORS = ['#3ED177','#2FBF5C','#1FBE5B','#20B85C','#1FB65A','#28C76F','#31B96E'];
function pickColor(i){ return COLORS[i % COLORS.length]; }

/* ---------------- 状态（持久化） ---------------- */
const state = {
  servers: LS.get('lu.servers', []),   // {id,name,url,userId,token,userName,version,color,added}
  cur:     LS.get('lu.cur', 'all'),
  hidden:  LS.get('lu.hidden', []),
  home:    LS.get('lu.home', null)
};
state.hiddenSet = new Set(state.hidden);

function save(){
  LS.set('lu.servers', state.servers);
  LS.set('lu.cur', state.cur);
  LS.set('lu.hidden', [...state.hiddenSet]);
  LS.set('lu.home', state.home);
}

function srv(id){ return state.servers.find(s=>s.id===id) || null; }
function targetSrv(id){ return srv(id || (state.cur==='all' ? null : state.cur)); }

/* ---------------- 底层请求 ---------------- */
async function req(server, path, opts = {}){
  const url = server.url.replace(/\/+$/, '') + path;
  const headers = Object.assign({
    'X-Emby-Authorization': authHeader()
  }, opts.headers || {});
  if(server.token) headers['X-Emby-Token'] = server.token;
  const res = await fetch(url, {
    method: opts.method || 'GET',
    headers,
    body: opts.body ? JSON.stringify(opts.body) : undefined
  });
  if(!res.ok){
    const err = new Error('Emby ' + res.status + ' ' + path);
    err.status = res.status;
    throw err;
  }
  const ct = res.headers.get('content-type') || '';
  return ct.includes('json') ? res.json() : res.text();
}

/* ---------------- 鉴权 / 服务器 ---------------- */
async function auth({ url, user, pass, name }){
  url = url.trim().replace(/\/+$/, '');
  if(!/^https?:\/\//.test(url)) url = 'http://' + url;
  const probe = { url, id: '', token: '' };
  const info = await req(probe, '/System/Info/Public');
  const r = await req(probe, '/Users/AuthenticateByName', {
    method: 'POST',
    body: { Username: user, Pw: pass }
  });
  const server = {
    id: 'srv-' + Math.random().toString(36).slice(2, 8),
    name: name || info.ServerName || user,
    url,
    userId: r.User.Id,
    token: r.AccessToken,
    userName: r.User.Name || user,
    version: info.Version || '?',
    color: pickColor(state.servers.length),
    added: Date.now()
  };
  state.servers.push(server);
  state.cur = server.id;
  save();
  return server;
}

async function verify(server){          // 校验 token 是否仍有效
  try{
    await req(server, '/System/Info');
    return true;
  }catch(e){
    if(e.status === 401) return false;
    return true;                        // 网络问题不当掉线处理
  }
}

function remove(id){
  state.servers = state.servers.filter(s=>s.id!==id);
  if(state.cur === id) state.cur = state.servers.length ? state.servers[0].id : 'all';
  save();
}

/* ---------------- 数据查询 ---------------- */
function userId(s){ return s.userId; }

async function views(s){                 // 媒体库列表
  const r = await req(s, '/Users/' + userId(s) + '/Views');
  return (r.Items || []).map(v=>({
    id: v.Id, name: v.Name, type: v.CollectionType || 'folder',
    srvId: s.id
  }));
}

async function counts(s){                // 库统计（影片/剧集数量）
  const r = await req(s, '/Items/Counts');
  return { movies: r.MovieCount || 0, series: r.SeriesCount || 0, episodes: r.EpisodeCount || 0 };
}

async function resumeItems(s, limit = 14){
  const r = await req(s, '/Users/' + userId(s) + '/Items/Resume?Limit=' + limit + '&MediaTypes=Video&Fields=Overview,ProductionYear,SeriesName');
  return (r.Items || []).map(it => wrap(s, it));
}

async function latestItems(s, parentId, limit = 14){
  let p = '/Users/' + userId(s) + '/Items/Latest?Limit=' + limit + '&Fields=Overview,ProductionYear';
  if(parentId) p += '&ParentId=' + parentId;
  const r = await req(s, p);
  return (Array.isArray(r) ? r : []).map(it => wrap(s, it));
}

async function items(s, q = {}){         // 通用列表查询
  let p = '/Users/' + userId(s) + '/Items?';
  const def = { Recursive: 'true', SortBy: 'SortName', SortOrder: 'Ascending', Limit: 60, Fields: 'Overview,ProductionYear,ChildCount' };
  const merged = Object.assign(def, q);
  if(merged.ParentId === undefined) delete merged.ParentId;
  p += Object.entries(merged).map(([k,v]) => k + '=' + encodeURIComponent(v)).join('&');
  const r = await req(s, p);
  return { total: r.TotalRecordCount || 0, items: (r.Items || []).map(it => wrap(s, it)) };
}

async function search(s, term, limit = 40){
  return items(s, { searchTerm: term, Limit: limit, SortBy: 'SortName' });
}

async function item(s, id){
  const r = await req(s, '/Users/' + userId(s) + '/Items/' + id);
  return wrap(s, r);
}

async function episodes(s, seriesId, seasonId){
  let p = '/Shows/' + seriesId + '/Episodes?UserId=' + userId(s) + '&Fields=Overview,ProductionYear';
  if(seasonId) p += '&SeasonId=' + seasonId;
  const r = await req(s, p);
  return (r.Items || []).map(it => wrap(s, it));
}

function wrap(s, it){
  return {
    srvId: s.id, srvName: s.name,
    id: it.Id, nm: it.Name, type: it.Type,
    seriesName: it.SeriesName || '',
    season: it.ParentIndexNumber, ep: it.IndexNumber,
    year: it.ProductionYear || '',
    overview: it.Overview || '',
    runMs: it.RunTimeTicks ? it.RunTimeTicks / 1e7 : 0,
    posSec: it.UserData && it.UserData.PlaybackPositionTicks ? it.UserData.PlaybackPositionTicks / 1e7 : 0,
    playedPct: it.UserData && it.UserData.PlayedPercentage ? it.UserData.PlayedPercentage : 0,
    childCount: it.ChildCount || 0,
    it: it
  };
}

/* ---------------- 媒体 URL ---------------- */
function imageUrl(s, itemId, type = 'Primary', maxW = 400){
  if(!itemId) return '';
  return s.url.replace(/\/+$/, '') + '/Items/' + itemId + '/Images/' + type + '?maxWidth=' + maxW + (s.token ? '&api_key=' + s.token : '');
}

function streamUrl(s, itemId){           // 直连播放（DirectPlay）
  return s.url.replace(/\/+$/, '') + '/Videos/' + itemId + '/stream.mp4?static=true' + (s.token ? '&api_key=' + s.token : '');
}

function hlsUrl(s, itemId){              // 转码播放（HLS，iOS 原生支持；Android WebView 需 hls.js）
  return s.url.replace(/\/+$/, '') + '/Videos/' + itemId + '/master.m3u8?MediaSourceId=' + itemId + (s.token ? '&api_key=' + s.token : '');
}

/* ---------------- 播放状态上报 ---------------- */
function ticks(sec){ return Math.round(sec * 1e7); }

function reportStart(s, itemId, posSec){
  req(s, '/Sessions/Playing', { method: 'POST', body: {
    ItemId: itemId, PositionTicks: ticks(posSec || 0), PlayMethod: 'DirectPlay'
  }}).catch(()=>{});
}
let progTimer = null;
function reportProgress(s, itemId, posSec, paused){
  req(s, '/Sessions/Playing/Progress', { method: 'POST', body: {
    ItemId: itemId, PositionTicks: ticks(posSec), IsPaused: !!paused
  }}).catch(()=>{});
}
function reportStop(s, itemId, posSec){
  req(s, '/Sessions/Playing/Stopped', { method: 'POST', body: {
    ItemId: itemId, PositionTicks: ticks(posSec)
  }}).catch(()=>{});
}
function autoProgress(s, itemId, posSec, paused){
  clearInterval(progTimer);
  progTimer = setInterval(()=> reportProgress(s, itemId, posSec(), paused()), 10000);
}
function stopAutoProgress(){
  clearInterval(progTimer);
  progTimer = null;
}

/* ---------------- 导出 ---------------- */
window.EBY = {
  state, save, srv, auth, verify, remove,
  views, counts, resumeItems, latestItems, items, search, item, episodes,
  imageUrl, streamUrl, hlsUrl,
  reportStart, reportProgress, reportStop, autoProgress, stopAutoProgress,
  fmtTime(sec){
    sec = Math.max(0, Math.round(sec || 0));
    const h = Math.floor(sec/3600), m = Math.floor(sec%3600/60), s2 = sec%60;
    const mm = (h? String(m).padStart(2,'0') : m), ss = String(s2).padStart(2,'0');
    return (h? h + ':' : '') + mm + ':' + ss;
  },
  fmtCount(n){
    n = n || 0;
    return n >= 10000 ? (n/10000).toFixed(1).replace(/\.0$/,'') + '万' : String(n);
  }
};
})();
