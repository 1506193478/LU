/* ============ LU · Bangumi API 客户端（追番真实数据层） ============ */
/* 与 LU Flutter 版同源端点：api.bgm.tv /v0 + /calendar。UA 由原生层附加（capacitor appendUserAgent）*/
(function(){
'use strict';

const BASE = 'https://api.bgm.tv';
const LS = {
  get(k, def){ try{ const v = localStorage.getItem(k); return v ? JSON.parse(v) : def; }catch(e){ return def; } },
  set(k, v){ try{ localStorage.setItem(k, JSON.stringify(v)); }catch(e){} }
};

const state = {
  token: LS.get('lu.bgm.token', ''),       // Bangumi Access Token（个人令牌）
  user:  LS.get('lu.bgm.user', null)
};

function headers(){
  const h = { 'Accept': 'application/json' };
  if(state.token) h['Authorization'] = 'Bearer ' + state.token;
  return h;
}

async function req(path, opts = {}){
  const res = await fetch(BASE + path, {
    method: opts.method || 'GET',
    headers: Object.assign(headers(), opts.headers || {}),
    body: opts.body ? JSON.stringify(opts.body) : undefined
  });
  if(!res.ok){ const e = new Error('Bangumi ' + res.status); e.status = res.status; throw e; }
  return res.json();
}

/* 每周放送日历：[{weekday:{cn,...}, items:[subject|{subject}]}] */
async function calendar(){
  const data = await req('/calendar');
  return data.map(day=>{
    const items = (day.items || []).map(x=> norm(x.subject || x));
    return { weekday: day.weekday ? day.weekday.cn : '', items };
  });
}

/* 条目搜索 */
async function search(keyword, limit = 20){
  const r = await req('/v0/search/subjects?limit=' + limit, {
    method: 'POST',
    body: { keyword, limit }
  });
  return (r.data || []).map(norm);
}

/* 条目详情 / 章节 */
async function subject(id){ return norm(await req('/v0/subjects/' + id)); }
async function episodes(id){
  const r = await req('/v0/subjects/' + id + '/episodes');
  return (r.data || []).map(e=>({ id: e.id, ep: e.ep, name: e.name_cn || e.name, dur: e.duration || '' }));
}

/* 当前用户（需要 token） */
async function me(){
  const u = await req('/v0/me');
  state.user = { id: u.id, name: u.username || u.nicknames && u.nicknames[0] || u.name, avatar: u.avatar && u.avatar.medium };
  LS.set('lu.bgm.user', state.user);
  return state.user;
}

/* 用户收藏（在看=2，想看=1，看过=3，搁置=4，抛弃=5） */
async function collections(type = 2, limit = 24){
  if(!state.user){
    state.user = LS.get('lu.bgm.user', null);
    if(!state.user) await me();
  }
  const u = state.user;
  const r = await req('/v0/users/' + (u.username || u.id) + '/collections?type=' + type + '&limit=' + limit + '&subject_type=2');
  return (r.data || []).map(x=> norm(x.subject)).filter(Boolean);
}

/* 统一字段 */
function norm(s){
  if(!s) return null;
  return {
    id: s.id,
    nm: s.name_cn || s.name,
    nmOrig: s.name,
    date: s.date || (s.air_date || ''),
    cover: s.images ? (s.images.large || s.images.common || s.images.medium) : '',
    score: s.rating && s.rating.score ? s.rating.score : 0,
    summary: s.summary || '',
    eps: s.eps_count || s.total_episodes || 0,
    airWeekday: s.air_weekday
  };
}

/* 登录：粘贴个人 Access Token（https://bgm.tv/dev/app 创建后获取） */
async function login(token){
  const prev = state.token;
  state.token = token.trim();
  try{
    const u = await me();
    LS.set('lu.bgm.token', state.token);
    return u;
  }catch(e){
    state.token = prev;
    throw e;
  }
}
function logout(){ state.token=''; state.user=null; LS.set('lu.bgm.token',''); LS.set('lu.bgm.user',null); }

window.BGM = { state, calendar, search, subject, episodes, me, collections, login, logout };
})();
