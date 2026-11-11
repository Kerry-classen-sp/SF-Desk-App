// A small stand-in for express.Router, for running the shared core's API where there is no HTTP server
// (JavaScriptCore in the iPhone app). Same handler shapes: (req, res, next), error handlers with four
// arguments, routes like '/accounts/:id'. Only the parts of req and res the core uses are there.

export function miniRouter() {
  const layers = [];
  const router = {};
  router.use = (...handlers) => { layers.push({ method: null, handlers }); return router; };
  for (const m of ['get', 'post', 'patch', 'put', 'delete']) {
    router[m] = (path, ...handlers) => {
      const keys = [];
      const re = new RegExp('^' + path.replace(/[.+?^${}()|[\]\\]/g, '\\$&')
        .replace(/:(\w+)/g, (_, k) => { keys.push(k); return '([^/]+)'; }) + '/?$');
      layers.push({ method: m.toUpperCase(), re, keys, handlers });
      return router;
    };
  }

  const matches = (layer, method, path) => {
    if (!layer.method) return {};
    if (layer.method !== method) return null;
    const m = layer.re.exec(path);
    return m && Object.fromEntries(layer.keys.map((k, i) => [k, decodeURIComponent(m[i + 1])]));
  };

  // One request: { method, url (after /api, with its query), headers, body, session }. Resolves to
  // { status, headers, body (text) }.
  router.handle = ({ method = 'GET', url, headers = {}, body, session }) => new Promise((resolve) => {
    const [path, qs = ''] = url.split('?');
    const query = {};
    for (const part of qs.split('&').filter(Boolean)) {
      const i = part.indexOf('=');
      const dec = (s) => decodeURIComponent(s.replace(/\+/g, ' '));
      const k = dec(i < 0 ? part : part.slice(0, i)), v = i < 0 ? '' : dec(part.slice(i + 1));
      query[k] = k in query ? [].concat(query[k], v) : v;
    }
    const lower = Object.fromEntries(Object.entries(headers).map(([k, v]) => [k.toLowerCase(), v]));
    const req = { method, url, path, originalUrl: '/api' + url, query, body, params: {}, session,
      get: (h) => lower[h.toLowerCase()] };
    const out = { status: 200, headers: {}, body: '' };
    let done = false;
    const res = {
      status(code) { out.status = code; return res; },
      set(k, v) { out.headers[k] = String(v); return res; },
      get(k) { return out.headers[Object.keys(out.headers).find((x) => x.toLowerCase() === k.toLowerCase())]; },
      type(t) { out.headers['Content-Type'] = t; return res; },
      json(v) { out.headers['Content-Type'] = 'application/json'; return res.send(JSON.stringify(v ?? null)); },
      send(b) {
        if (done) return res;
        done = true;
        out.body = typeof b === 'string' ? b : JSON.stringify(b);
        resolve(out);
        return res;
      },
    };

    let li = 0, layer = null, hi = 0;
    const next = (err) => {
      if (done) return;
      for (;;) {
        if (!layer || hi >= layer.handlers.length) {
          layer = null; hi = 0;
          while (li < layers.length) {
            const params = matches(layers[li++], method, path);
            if (params) { layer = layers[li - 1]; req.params = params; break; }
          }
          if (!layer) {
            if (err) return res.status(err.status || 500).json({ error: err.status ? err.message : 'Unexpected error' });
            return res.status(404).json({ error: 'Not found' });
          }
        }
        const h = layer.handlers[hi++];
        if (err ? h.length !== 4 : h.length === 4) continue;
        try {
          const r = err ? h(err, req, res, next) : h(req, res, next);
          if (r && typeof r.catch === 'function') r.catch(next);
        } catch (e) { next(e); }
        return;
      }
    };
    next();
  });

  return router;
}
