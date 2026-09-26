/* 牛室炙烤牛排 ERP · Service Worker
   目前用于：安装为 App、以及订单通知(前台 showNotification)。
   预留 push 事件处理，供日后接入后台推送(需服务器/Edge Function 发送)。
   2026-09-26：加入 fetch 拦截，网页(navigate)/index.html 一律「网络优先」，
   确保安装到手机主屏幕的 App 每次打开都会先尝试抓最新版本，抓不到(离线)才退回快取，
   避免安装后卡在旧版本、要删除重装才能看到更新。 */
self.addEventListener('install', e => self.skipWaiting());
self.addEventListener('message', e => { if(e.data==='skipWaiting') self.skipWaiting(); });
self.addEventListener('activate', e => e.waitUntil((async()=>{
  const keys=await caches.keys();
  await Promise.all(keys.filter(k=>k!=='bh-erp-v1').map(k=>caches.delete(k)));
  await self.clients.claim();
})()));

self.addEventListener('fetch', event => {
  const req=event.request;
  if(req.method!=='GET')return;
  // 页面导航(打开/刷新 App) 或 index.html 本身：网络优先，拿到就直接用+更新快取；
  // 网络失败(离线)才退回快取版本，保证离线仍能开启。
  if(req.mode==='navigate' || req.url.endsWith('index.html') || req.url.endsWith('/')){
    event.respondWith((async()=>{
      try{
        const fresh=await fetch(req,{cache:'no-store'});
        const cache=await caches.open('bh-erp-v1');
        cache.put(req,fresh.clone());
        return fresh;
      }catch(e){
        const cached=await caches.match(req);
        return cached||Response.error();
      }
    })());
  }
});

// 后台推送(需服务器发送 Web Push；未接入时此段不会触发)
self.addEventListener('push', event => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch (e) { data = { body: event.data && event.data.text() }; }
  const title = data.title || '🔔 新订单 New Order';
  const options = { body: data.body || '', tag: data.tag || 'order', renotify: true, requireInteraction: true, vibrate: [300, 120, 300, 120, 300], data: { url: data.url || './' } };
  if (data.icon) { options.icon = data.icon; options.badge = data.icon; }
  event.waitUntil(self.registration.showNotification(title, options));
});

// 点通知 → 打开/聚焦网站
self.addEventListener('notificationclick', event => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
      for (const c of list) { if ('focus' in c) return c.focus(); }
      if (clients.openWindow) return clients.openWindow('./');
    })
  );
});
