// Arco Ríos · recibe los avisos y los muestra como notificación del teléfono.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (e) => e.waitUntil(self.clients.claim()));

self.addEventListener("push", (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch { d = { cuerpo: e.data ? e.data.text() : "" }; }
  e.waitUntil(self.registration.showNotification(d.titulo || "Arco Ríos", {
    body: d.cuerpo || "",
    icon: "icon-192.png",
    badge: "badge-96.png",
    tag: d.tag || undefined,
    data: { url: d.url || "./" },
  }));
});

self.addEventListener("notificationclick", (e) => {
  e.notification.close();
  const url = new URL(e.notification.data?.url || "./", self.registration.scope).href;
  e.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((cs) => {
    for (const c of cs) {
      if (c.url.startsWith(self.registration.scope)) { c.postMessage({ tipo: "abrir", url }); return c.focus(); }
    }
    return self.clients.openWindow(url);
  }));
});
