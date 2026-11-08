/* ============ LU · 规则引擎（番剧第三方源解析，兼容 Kazumi 规则 apiLevel 9） ============ */
/* 与 LU Flutter 版 lib/plugins + lib/services/plugin/xpath_rule_strategy.dart 语义一致：
   规则仓库 index.json → 安装规则 → 搜索(@keyword) → 详情(roads/chapters) → 播放页解析视频直链。
   XPath 在 WebView 内用原生 DOMParser + document.evaluate 求值。 */
(function(){
'use strict';

const LS = {
  get(k, def){ try{ const v = localStorage.getItem(k); return v ? JSON.parse(v) : def; }catch(e){ return def; } },
  set(k, v){ try{ localStorage.setItem(k, JSON.stringify(v)); }catch(e){} }
};

const REPO_BASE = 'https://raw.githubusercontent.com/Predidit/KazumiRules/main/';

const state = {
  installed: LS.get('lu.rules', []),        // 已安装规则（Plugin JSON 原样）
  selected: LS.get('lu.rule.selected', '')  // 当前使用的规则名
};
function save(){ LS.set('lu.rules', state.installed); LS.set('lu.rule.selected', state.selected); }

/* ---------------- 仓库 ---------------- */
async function repoList(){
  const res = await fetch(REPO_BASE + 'index.json');
  if(!res.ok) throw new Error('仓库 index.json ' + res.status);
  return res.json();   // [{name, fileName, ...}]
}
async function install(fileName){
  const res = await fetch(REPO_BASE + fileName);
  if(!res.ok) throw new Error('规则下载失败 ' + res.status);
  const json = await res.json();
  return installRaw(json);
}
function installRaw(json){
  const name = json.name || json.webName || '未命名规则';
  const old = state.installed.findIndex(r=> (r.name||'') === name);
  if(old >= 0) state.installed[old] = json; else state.installed.push(json);
  if(!state.selected) state.selected = name;
  save();
  return name;
}
function uninstall(name){
  state.installed = state.installed.filter(r=> (r.name||'') !== name);
  if(state.selected === name) state.selected = state.installed.length ? state.installed[0].name : '';
  save();
}
function selected(){ return state.installed.find(r=> (r.name||'') === state.selected) || state.installed[0] || null; }
function select(name){ state.selected = name; save(); }

/* ---------------- 工具 ---------------- */
function joinUrl(base, rel){
  if(/^https?:\/\//i.test(rel)) return rel;
  base = (base||'').replace(/\/+$/, '');
  if(rel.startsWith('/')) return base + rel;
  return base + '/' + rel;
}

async function fetchPage(url, rule, referer){
  const headers = {};
  if(rule.userAgent) headers['User-Agent'] = rule.userAgent;
  const ref = referer || rule.baseUrl;
  if(ref) headers['Referer'] = ref;
  const res = await fetch(url, { headers });
  if(!res.ok) throw new Error('页面请求 ' + res.status);
  return res.text();
}

/* XPath 求值：返回单个节点 / 字符串 */
function xp(doc, expr, ctxNode){
  const r = doc.evaluate(expr, ctxNode || doc, null, XPathResult.ANY_TYPE, null);
  if(r.resultType === XPathResult.STRING_TYPE) return r.stringValue;
  if(r.resultType === XPathResult.FIRST_ORDERED_NODE_TYPE) return r.singleNodeValue;
  const nodes = [];
  let n;
  while((n = r.iterateNext())) nodes.push(n);
  return nodes.length === 1 ? nodes[0] : nodes;
}
function nodesOf(doc, expr, ctxNode){
  const r = doc.evaluate(expr, ctxNode || doc, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
  const out = [];
  for(let i=0;i<r.snapshotLength;i++) out.push(r.snapshotItem(i));
  return out;
}
function absUrl(doc, el, base){
  // 优先 href 属性（相对地址按 base 解析）
  const href = el.getAttribute && (el.getAttribute('href') || el.getAttribute('data-href') || el.getAttribute('src'));
  if(!href) return (el.textContent||'').trim();
  try{ return new URL(href, base).href; }catch(e){ return joinUrl(base, href); }
}

/* ---------------- 搜索（xpath / api 双模式） ---------------- */
async function search(rule, keyword){
  if(rule.searchMode === 'api') return searchApi(rule, keyword);
  const url = joinUrl(rule.baseUrl, rule.searchURL.replace('@keyword', encodeURIComponent(keyword)));
  const html = await fetchPage(url, rule);
  const doc = new DOMParser().parseFromString(html, 'text/html');
  const items = nodesOf(doc, rule.searchList);
  const out = [];
  items.forEach(node=>{
    let name = '', link = '';
    try{
      const nEl = xp(doc, rule.searchName, node);
      name = typeof nEl === 'string' ? nEl : (nEl && (nEl.textContent||'').trim() || '');
      const rEl = xp(doc, rule.searchResult, node);
      link = typeof rEl === 'string' ? rEl : absUrl(doc, rEl, rule.baseUrl);
    }catch(e){}
    if(name && link) out.push({ name: name.replace(/\s+/g,''), url: link });
  });
  return out;
}

async function searchApi(rule, keyword){
  const c = rule.searchApiConfig || {};
  const reqC = c.request || {};
  let url = (reqC.url || '').replace('@keyword', encodeURIComponent(keyword));
  url = joinUrl(rule.baseUrl, url);
  const opt = { method: reqC.method || 'GET', headers: Object.assign({}, reqC.headers||{}) };
  if(reqC.bodyType === 'json' && reqC.body){
    opt.headers['Content-Type'] = 'application/json';
    opt.body = JSON.stringify(reqC.body).replace('@keyword', encodeURIComponent(keyword));
  } else if(reqC.bodyType === 'form' && reqC.body){
    opt.headers['Content-Type'] = 'application/x-www-form-urlencoded';
    const parts = Object.entries(reqC.body||{}).map(([k,v])=> k+'='+encodeURIComponent(String(v).replace('@keyword', keyword)));
    opt.body = parts.join('&');
  }
  const res = await fetch(url, opt);
  if(!res.ok) throw new Error('API 搜索 ' + res.status);
  const data = await res.json();
  const pick = (obj, path) => path.split('.').reduce((o,k)=> o && o[k], obj);
  const list = pick(data, c.listPath || 'data') || [];
  return (Array.isArray(list) ? list : []).map(it=>({
    name: String(pick(it, c.namePath || 'name') || '').replace(/\s+/g,''),
    url: String(pick(it, c.sourcePath || 'source') || '')
  })).filter(x=>x.name && x.url);
}

/* ---------------- 详情（roads + chapters） ---------------- */
async function roads(rule, detailUrl){
  if(rule.chapterMode === 'api') return roadsApi(rule, detailUrl);
  const html = await fetchPage(detailUrl, rule);
  const doc = new DOMParser().parseFromString(html, 'text/html');
  const roadNodes = nodesOf(doc, rule.chapterRoads);
  const out = [];
  roadNodes.forEach(rn=>{
    const name = (rn.textContent||'').replace(/\s+/g,' ').trim().slice(0,30) || ('线路'+(out.length+1));
    const eps = nodesOf(doc, rule.chapterResult, rn).map((el,i)=>({
      name: (el.textContent||'').replace(/\s+/g,'').trim() || ('第'+(i+1)+'集'),
      url: absUrl(doc, el, detailUrl || rule.baseUrl)
    })).filter(x=>x.url);
    if(eps.length) out.push({ name, chapters: eps });
  });
  return out;
}

async function roadsApi(rule, detailUrl){
  const c = rule.chapterApiConfig || {};
  const reqC = c.request || {};
  let url = (reqC.url || '').replace('@source', detailUrl);
  url = joinUrl(rule.baseUrl, url);
  const res = await fetch(url, { method: reqC.method || 'GET', headers: reqC.headers||{} });
  if(!res.ok) throw new Error('API 章节 ' + res.status);
  const data = await res.json();
  const pick = (obj, path) => path.split('.').reduce((o,k)=> o && o[k], obj);
  const list = pick(data, c.listPath || 'data') || [];
  const fmt = c.episodeFormat || 'nested';
  const out = [];
  (Array.isArray(list) ? list : []).forEach((road, i)=>{
    const rname = String(pick(road, c.namePath || 'name') || ('线路'+(i+1)));
    let eps = [];
    if(fmt === 'nested'){
      eps = (pick(road, c.episodeListPath || 'list') || []).map((e,j)=>({
        name: String(pick(e, c.episodeNamePath || 'name') || '第'+(j+1)+'集'),
        url: String(pick(e, c.episodeSourcePath || 'source') || '')
      }));
    } else {
      // delimited：episodeSourcePath 指向的分集串，用 episodeDelimitedCharacter 分割
      const raw = String(pick(road, c.episodeSourcePath || '') || '');
      const names = raw.split(c.episodeDelimitedCharacter || '#');
      eps = names.map((n,j)=>({ name: n.trim() || ('第'+(j+1)+'集'), url: raw.split(c.episodeDelimitedCharacter || '#')[j] || n }));
    }
    eps = eps.filter(x=>x.url);
    if(eps.length) out.push({ name: rname, chapters: eps });
  });
  return out;
}

/* ---------------- 播放页 → 视频直链 ---------------- */
const STREAM_RE = /(https?:\/\/[^"'\s<>\\]+?\.(?:m3u8|mp4|flv|mkv|ts)[^"'\s<>\\]*)/i;

async function resolvePlay(rule, playUrl, referer){
  // 1) 播放地址本身已是视频直链
  if(STREAM_RE.test(playUrl)) return playUrl;
  // 2) 拉取播放页，提取内嵌的视频直链（绝大多数规则站直接内嵌 m3u8/mp4）
  const html = await fetchPage(playUrl, rule, rule.baseUrl);
  const m = html.match(STREAM_RE);
  if(m) return m[1];
  // 3) 常见 player 配置变量兜底
  const v = html.match(/(?:video_url|url|playUrl|source)\s*[:=]\s*['"](https?:\/\/[^'"]+?\.(?:m3u8|mp4))['"]/i);
  if(v) return v[1];
  throw new Error('未在播放页中找到视频直链（该站可能需要 WebView 抓取）');
}

/* ---------------- 导出 ---------------- */
window.RULES = {
  state, save, repoList, install, installRaw, uninstall, selected, select,
  search, roads, resolvePlay, REPO_BASE
};
})();
