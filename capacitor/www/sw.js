/* LU · PWA Service Worker：预缓存应用外壳，运行时缓存优先、网络兜底 */
const CACHE = 'lu-shell-v1';
const SHELL = [
  './',
  './index.html',
  './manifest.json',
  './assets/icons/icon-app-192.png',
  './assets/icons/icon-app-512.png',
  './assets/icons/icon-light-sakura.jpg',
  './assets/icons/icon-dark-yuki.jpg',
  './assets/icons/icon-alt-wolf.png',
  './assets/icons/icon-alt-mint.png',
  './assets/icons/icon-alt-devil.png',
  './assets/icons/icon-alt-shiba.png'
];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  const url = new URL(e.request.url);
  if (url.origin !== location.origin) return; // 外部 Emby 流量不拦截
  e.respondWith(
    caches.match(e.request).then(hit => hit || fetch(e.request).then(res => {
      const copy = res.clone();
      caches.open(CACHE).then(c => c.put(e.request, copy));
      return res;
    }).catch(() => caches.match('./index.html')))
  );
});
