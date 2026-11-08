/* Karte: MapLibre (via mapgl widget) + filters. Reads only files from export/data.
   Basemap tiles (Carto) are the only third-party request of the whole site. */
(function () {
  'use strict';
  var SEV = ['Sachschaden', 'Leichtverletzte', 'Schwerverletzte', 'Getötete'];
  var PALETTE = {
    light: { style: 'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json',
      sev: ['#9ec5f4', '#3987e5', '#1b4f9e', '#0d366b'], stroke: '#ffffff', fatalStroke: '#ffffff',
      heat: ['rgba(205,226,251,0)', '#cde2fb', '#9ec5f4', '#3987e5', '#1b4f9e', '#0d366b'],
      choro: ['#e8f1fd', '#b7d4f7', '#6aa6ec', '#2a78d6', '#0d366b'], line: '#6b6a64' },
    dark: { style: 'https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json',
      sev: ['#35669f', '#3987e5', '#9ec5f4', '#f0efec'], stroke: '#1a1a19', fatalStroke: '#1a1a19',
      heat: ['rgba(18,41,74,0)', '#1f4a80', '#2a78d6', '#6aa6ec', '#b7d4f7', '#f0efec'],
      choro: ['#14304f', '#1f4a80', '#2a78d6', '#7db1f2', '#cde2fb'], line: '#a9a8a2' }
  };
  var BREAKS = [1.5, 2.5, 4, 8];
  var BREAK_LABELS = ['unter 1.5', '1.5 – 2.5', '2.5 – 4', '4 – 8', 'über 8'];
  var fmt = function (n) { return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, '’'); };

  var root = document.getElementById('zmap');
  if (!root) return;
  var ui = {
    y0: document.getElementById('zm-y0'), y1: document.getElementById('zm-y1'),
    status: document.getElementById('zm-status'), legend: document.getElementById('zm-legend'),
    sev: document.querySelectorAll('input[name=zm-sev]'),
    mode: document.querySelectorAll('input[name=zm-mode]'),
    view: document.querySelectorAll('input[name=zm-view]'),
    qrt: document.getElementById('zm-qrt')
  };
  var state = { y0: 2011, y1: 2024, sev: [0, 1, 2, 3], mode: 'alle', view: 'heat', qrt: false };
  var data = null, quartiere = null, map = null;
  var abs = function (p) { return new URL('export/data/' + p, document.baseURI).href; };
  var isDark = function () { return document.body.classList.contains('quarto-dark'); };
  var pal = function () { return isDark() ? PALETTE.dark : PALETTE.light; };

  [ui.y0, ui.y1].forEach(function (sel, k) {
    for (var y = 2011; y <= 2024; y++) { var o = document.createElement('option'); o.value = y; o.textContent = y; sel.appendChild(o); }
    sel.value = k ? 2024 : 2011;
  });

  function setStatus(t) { if (ui.status) ui.status.textContent = t; }

  function filterExpr() {
    var f = ['all', ['>=', ['get', 'j'], state.y0], ['<=', ['get', 'j'], state.y1],
      ['in', ['get', 's'], ['literal', state.sev]]];
    if (state.mode === 'velo') f.push(['==', ['get', 'v'], 1]);
    if (state.mode === 'fuss') f.push(['==', ['get', 'f'], 1]);
    if (state.mode === 'moto') f.push(['==', ['get', 'm'], 1]);
    return f;
  }

  function count() {
    if (!data) return;
    var n = 0, total = 0, break15 = state.y0 < 2015 && state.y1 >= 2015 && state.sev.indexOf(0) >= 0;
    var feats = data.features;
    for (var i = 0; i < feats.length; i++) {
      var p = feats[i].properties, g = feats[i].geometry;
      // features may be Point or MultiPoint (one feature per distinct attribute combination)
      var w = g && g.type === 'MultiPoint' ? g.coordinates.length : 1;
      total += w;
      if (p.j < state.y0 || p.j > state.y1 || state.sev.indexOf(p.s) < 0) continue;
      if (state.mode === 'velo' && p.v !== 1) continue;
      if (state.mode === 'fuss' && p.f !== 1) continue;
      if (state.mode === 'moto' && p.m !== 1) continue;
      n += w;
    }
    setStatus(fmt(n) + ' von ' + fmt(total) + ' Unfällen angezeigt.' +
      (break15 ? ' Hinweis: Sachschaden-Unfälle sind vor und ab 2015 nicht vergleichbar (Änderung der Erfassungspraxis).' : ''));
  }

  function addAll() {
    var P = pal();
    if (!map.getSource('unf')) map.addSource('unf', { type: 'geojson', data: data });
    if (!map.getSource('qrt')) map.addSource('qrt', { type: 'geojson', data: quartiere });
    var step = ['step', ['get', 'rate'], P.choro[0]];
    BREAKS.forEach(function (b, i) { step.push(b, P.choro[i + 1]); });
    ['qrt-fill', 'qrt-line', 'heat', 'pts'].forEach(function (id) { if (map.getLayer(id)) map.removeLayer(id); });
    map.addLayer({ id: 'qrt-fill', type: 'fill', source: 'qrt', paint: { 'fill-color': step, 'fill-opacity': 0.78 },
      layout: { visibility: state.qrt ? 'visible' : 'none' } });
    map.addLayer({ id: 'qrt-line', type: 'line', source: 'qrt', paint: { 'line-color': P.line, 'line-width': 0.8, 'line-opacity': 0.8 },
      layout: { visibility: state.qrt ? 'visible' : 'none' } });
    var heatColor = ['interpolate', ['linear'], ['heatmap-density'], 0, P.heat[0], 0.1, P.heat[1], 0.3, P.heat[2], 0.5, P.heat[3], 0.75, P.heat[4], 1, P.heat[5]];
    map.addLayer({ id: 'heat', type: 'heatmap', source: 'unf', maxzoom: 17,
      paint: { 'heatmap-weight': 0.06,
        'heatmap-intensity': ['interpolate', ['linear'], ['zoom'], 10, 0.6, 13, 1, 16, 2.5],
        'heatmap-radius': ['interpolate', ['linear'], ['zoom'], 10, 4, 13, 9, 16, 20],
        'heatmap-color': heatColor,
        'heatmap-opacity': ['interpolate', ['linear'], ['zoom'], 14, 0.9, 16.5, 0.15] } });
    map.addLayer({ id: 'pts', type: 'circle', source: 'unf',
      paint: {
        'circle-color': ['match', ['get', 's'], 0, P.sev[0], 1, P.sev[1], 2, P.sev[2], P.sev[3]],
        'circle-radius': ['interpolate', ['linear'], ['zoom'], 10, ['case', ['==', ['get', 's'], 3], 3, 1.2], 16, ['case', ['==', ['get', 's'], 3], 8, 4.5]],
        'circle-stroke-color': P.stroke, 'circle-stroke-width': ['case', ['==', ['get', 's'], 3], 1.2, 0.4],
        'circle-opacity': 0.9 } });
    apply();
  }

  function apply() {
    if (!map || !map.getLayer('pts')) return;
    var f = filterExpr();
    map.setFilter('heat', f); map.setFilter('pts', f);
    var heatOn = state.view === 'heat';
    map.setLayoutProperty('heat', 'visibility', heatOn ? 'visible' : 'none');
    map.setLayoutProperty('pts', 'visibility', 'visible');
    var ptsOpacity = heatOn ? ['interpolate', ['linear'], ['zoom'], 13.5, 0, 15, 0.9] : 0.9;
    map.setPaintProperty('pts', 'circle-opacity', ptsOpacity);
    map.setPaintProperty('pts', 'circle-stroke-opacity', ptsOpacity);
    var vis = state.qrt ? 'visible' : 'none';
    map.setLayoutProperty('qrt-fill', 'visibility', vis); map.setLayoutProperty('qrt-line', 'visibility', vis);
    count(); legend();
  }

  function legend() {
    if (!ui.legend) return;
    var P = pal(), h = '';
    h += '<span><strong>Einzelpunkte (ab Zoomstufe 14 oder im Modus «Einzelpunkte»):</strong></span>';
    SEV.forEach(function (s, i) { h += '<span><i style="background:' + P.sev[i] + ';width:.8rem;height:.8rem;border-radius:50%"></i>' + s + '</span>'; });
    if (state.qrt) {
      h += '<span style="flex-basis:100%"></span><span><strong>Quartiere, Unfälle mit Personenschaden pro 1’000 Einw. und Jahr (2015–2024):</strong></span>';
      BREAK_LABELS.forEach(function (l, i) { h += '<span><i style="background:' + P.choro[i] + '"></i>' + l + '</span>'; });
    }
    ui.legend.innerHTML = h;
  }

  function wire() {
    function readYears(src) {
      var a = +ui.y0.value, b = +ui.y1.value;
      if (a > b) { if (src === ui.y0) { b = a; ui.y1.value = b; } else { a = b; ui.y0.value = a; } }
      state.y0 = a; state.y1 = b; apply();
    }
    ui.y0.addEventListener('change', function () { readYears(ui.y0); });
    ui.y1.addEventListener('change', function () { readYears(ui.y1); });
    Array.prototype.forEach.call(ui.sev, function (c) {
      c.addEventListener('change', function () {
        state.sev = Array.prototype.filter.call(ui.sev, function (x) { return x.checked; }).map(function (x) { return +x.value; });
        apply();
      });
    });
    Array.prototype.forEach.call(ui.mode, function (r) { r.addEventListener('change', function () { if (r.checked) { state.mode = r.value; apply(); } }); });
    Array.prototype.forEach.call(ui.view, function (r) { r.addEventListener('change', function () { if (r.checked) { state.view = r.value; apply(); } }); });
    ui.qrt.addEventListener('change', function () { state.qrt = ui.qrt.checked; apply(); });
  }

  function interactions() {
    var popup = new maplibregl.Popup({ closeButton: true, maxWidth: '260px' });
    map.on('click', 'pts', function (e) {
      var p = e.features[0].properties, who = [];
      if (+p.v) who.push('Velo'); if (+p.f) who.push('Fussgänger:in'); if (+p.m) who.push('Motorrad');
      popup.setLngLat(e.lngLat).setHTML('<strong>' + p.j + '</strong> · ' + SEV[+p.s] + (who.length ? '<br>Beteiligt: ' + who.join(', ') : '')).addTo(map);
    });
    map.on('click', 'qrt-fill', function (e) {
      if (map.queryRenderedFeatures(e.point, { layers: ['pts'] }).length && state.view === 'points') return;
      var p = e.features[0].properties;
      popup.setLngLat(e.lngLat).setHTML('<strong>' + p.quartier + '</strong> (Kreis ' + p.kreis_nr + ')<br>' + p.rate + ' Unfälle mit Personenschaden pro 1’000 Einw. und Jahr').addTo(map);
    });
    ['pts', 'qrt-fill'].forEach(function (l) {
      map.on('mouseenter', l, function () { map.getCanvas().style.cursor = 'pointer'; });
      map.on('mouseleave', l, function () { map.getCanvas().style.cursor = ''; });
    });
  }

  function start(widgetEl) {
    map = widgetEl.map;
    var init = function () {
      if (!map.__znav) { map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right'); map.__znav = true; }
      addAll(); interactions(); wire();
      new MutationObserver(function () {
        var want = pal().style;
        if (map.__zstyle === want) return;
        map.__zstyle = want;
        map.once('style.load', addAll);
        map.setStyle(want, { diff: false });
      }).observe(document.body, { attributes: true, attributeFilter: ['class'] });
    };
    // switch to the dark basemap right away when the theme is dark
    var want = pal().style; map.__zstyle = want;
    var go = function () { if (isDark()) { map.once('style.load', init); map.setStyle(want, { diff: false }); } else init(); };
    if (map.loaded()) go(); else map.once('load', go);
  }

  setStatus('Lade Unfalldaten …');
  Promise.all([fetch(abs('unfaelle_punkte.geojson')).then(function (r) { return r.json(); }),
               fetch(abs('quartiere.geojson')).then(function (r) { return r.json(); })])
    .then(function (res) {
      data = res[0]; quartiere = res[1];
      var tries = 0, t = setInterval(function () {
        var w = root.querySelector('.html-widget');
        if (w && w.map) { clearInterval(t); start(w); }
        else if (++tries > 100) { clearInterval(t); setStatus('Die Karte konnte nicht gestartet werden. Bitte die Tabelle unten verwenden.'); }
      }, 100);
    })
    .catch(function () { setStatus('Die Daten konnten nicht geladen werden. Bitte die Tabelle unten verwenden.'); });
})();
