const CACHE='streetwise-commercial-v1';
const ASSETS=['./','./index.html','./manifest.json','./config.js','./icon-192.png','./icon-512.png'];
self.addEventListener('install',e=>e.waitUntil(caches.open(CACHE).then(c=>c.addAll(ASSETS)).then(()=>self.skipWaiting())));
self.addEventListener('activate',e=>e.waitUntil(self.clients.claim()));
self.addEventListener('fetch',e=>e.respondWith(caches.match(e.request).then(r=>r||fetch(e.request).then(x=>{if(e.request.method==='GET'&&new URL(e.request.url).origin===location.origin){const c=x.clone();caches.open(CACHE).then(cache=>cache.put(e.request,c))}return x}).catch(()=>caches.match('./index.html')))));
