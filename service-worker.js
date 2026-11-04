const CACHE_NAME='oravena-shell-v29';
const APP_SHELL=['./','./index.html','./about.html','./styles.css','./login.css','./story.css','./editorial.css','./cinematic.css','./app.js','./about.js','./pwa.js','./manifest.webmanifest','./assets/oravena-icon-new.png','./assets/oravena-logo-new.png','./assets/oravena-adult-odontogram.png'];
self.addEventListener('install',event=>event.waitUntil(caches.open(CACHE_NAME).then(cache=>Promise.allSettled(APP_SHELL.map(url=>cache.add(url)))).then(()=>self.skipWaiting())));
self.addEventListener('activate',event=>event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key!==CACHE_NAME).map(key=>caches.delete(key)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',event=>{
  const request=event.request,url=new URL(request.url);
  if(request.method!=='GET'||url.origin!==location.origin)return;
  if(/\/(system|login)\.html$/.test(url.pathname)||/\/(dashboard|login|supabase-client|supabase-config)\.js$/.test(url.pathname)){
    event.respondWith(fetch(request,{cache:'no-store'}));
    return;
  }
  if(request.mode==='navigate'){
    event.respondWith(fetch(request).then(response=>{const copy=response.clone();caches.open(CACHE_NAME).then(cache=>cache.put(request,copy));return response}).catch(()=>caches.match(request).then(hit=>hit||caches.match('./index.html'))));
    return;
  }
  event.respondWith(caches.match(request).then(hit=>hit||fetch(request).then(response=>{if(response.ok){const copy=response.clone();caches.open(CACHE_NAME).then(cache=>cache.put(request,copy))}return response})));
});
