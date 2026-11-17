/* CTP internal hub: renders links.yaml plus live data from ctp-common.
 *
 * Data sources, in order of preference:
 *   links.yaml                      this repo (internal-only links)
 *   data/ctp-common/*.yaml          copied onto the server by deploy/deploy.sh
 *   raw.githubusercontent.com/...   fallback, e.g. for local preview
 *
 * No build step: edit links.yaml, push, deploy.
 */
(function () {
  'use strict';

  var ICONS = 'assets/img/icons.svg';
  var COMMON_FILES = ['links.yaml', 'people.yaml', 'clusters.yaml'];

  // ---------- small helpers ----------
  function el(tag, attrs, children) {
    var node = document.createElement(tag);
    if (attrs) {
      Object.keys(attrs).forEach(function (k) {
        var v = attrs[k];
        if (v === null || v === undefined || v === false) return;
        if (k === 'text') node.textContent = v;
        else if (k === 'class') node.className = v;
        else node.setAttribute(k, v);
      });
    }
    (children || []).forEach(function (c) {
      if (c === null || c === undefined || c === false) return;
      node.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
    });
    return node;
  }

  function icon(name, cls) {
    var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('class', 'icon' + (cls ? ' ' + cls : ''));
    svg.setAttribute('aria-hidden', 'true');
    var use = document.createElementNS('http://www.w3.org/2000/svg', 'use');
    use.setAttribute('href', ICONS + '#i-' + (name || 'link'));
    svg.appendChild(use);
    return svg;
  }

  function get(obj, dotted) {
    return String(dotted).split('.').reduce(function (o, k) {
      return o && Object.prototype.hasOwnProperty.call(o, k) ? o[k] : undefined;
    }, obj);
  }

  function join(base, path) {
    return String(base).replace(/\/+$/, '') + '/' + String(path).replace(/^\/+/, '');
  }

  function fetchText(url) {
    return fetch(url, { cache: 'no-cache' }).then(function (r) {
      if (!r.ok) throw new Error(url + ' → HTTP ' + r.status);
      return r.text();
    });
  }

  function fetchYaml(url) {
    return fetchText(url).then(function (t) { return jsyaml.load(t) || {}; });
  }

  function firstOk(urls) {
    var i = 0;
    function next(err) {
      if (i >= urls.length) return Promise.reject(err || new Error('no source'));
      var url = urls[i++];
      return fetchYaml(url).then(function (data) { return { data: data, url: url }; }, next);
    }
    return next();
  }

  // ---------- link resolution ----------
  var state = { cfg: {}, common: {}, people: {}, clusters: {}, byId: {} };

  function resolve(link, depth) {
    depth = depth || 0;
    var s = state.cfg.sources || {};
    if (!link) return { unset: 'Missing link' };
    if (link.ref) {
      if (depth > 3 || !state.byId[link.ref]) return { unset: 'Unknown ref: ' + link.ref };
      return resolve(state.byId[link.ref], depth + 1);
    }
    if ('url' in link) return link.url ? { href: link.url } : { unset: 'Link not set' };
    if (link.common) {
      var v = get(state.common, link.common);
      return v ? { href: v } : { unset: state.commonError ? 'ctp-common unavailable' : 'Not in ctp-common' };
    }
    if (link.docs !== undefined) return { href: join(s.docs_site, link.docs) };
    if (link.repo) return { href: join(s.github_org, link.repo) };
    if (link.pages) return { href: join(s.pages_base, link.pages) };
    return { unset: 'Link not set' };
  }

  function searchText(parts) {
    return parts.filter(Boolean).join(' ').toLowerCase();
  }

  // ---------- renderers ----------
  function renderHighlights(items) {
    var root = document.getElementById('highlights');
    root.textContent = '';
    (items || []).forEach(function (h) {
      var r = resolve(h);
      var head = el('div', { class: 'tile-head' }, [icon(h.icon), el('span', { class: 'tile-title', text: h.title })]);
      var desc = el('p', { class: 'tile-desc' }, [h.description || '']);
      if (h.note) { desc.appendChild(document.createTextNode(' ')); desc.appendChild(el('span', { class: 'pill', text: h.note })); }
      if (r.unset) desc.appendChild(el('span', { class: 'pill warn', text: r.unset }));
      var tile = el(r.href ? 'a' : 'div', {
        class: 'tile' + (r.href ? '' : ' unset'),
        href: r.href,
        'data-search': searchText([h.title, h.description, h.note])
      }, [head, desc, r.href ? icon('arrow-up-right', 'arrow') : null]);
      root.appendChild(tile);
    });
  }

  function linkRow(l) {
    var r = resolve(l);
    var body = el('span', { class: 'link-body' }, [
      el('span', { class: 'link-title', text: l.title }),
      l.note ? ' ' : null,
      l.note ? el('span', { class: 'pill', text: l.note }) : null,
      r.unset ? ' ' : null,
      r.unset ? el('span', { class: 'pill warn', text: r.unset }) : null,
      l.description ? el('span', { class: 'link-desc', text: l.description }) : null
    ]);
    var row = el(r.href ? 'a' : 'div', { class: 'link-row' + (r.href ? '' : ' unset'), href: r.href },
      [icon(l.icon), body, r.href ? icon('arrow-up-right', 'arrow') : null]);
    return el('li', { 'data-search': searchText([l.title, l.description, l.note]) }, [row]);
  }

  function renderSections(sections) {
    var root = document.getElementById('sections');
    root.textContent = '';
    (sections || []).forEach(function (sec, i) {
      var id = 'sec-' + i;
      var list = el('ul', { class: 'links' }, (sec.links || []).map(linkRow));
      root.appendChild(el('section', { class: 'block', 'aria-labelledby': id, 'data-section': '' }, [
        el('h2', { class: 'label', id: id, text: sec.title }), list
      ]));
    });
  }

  function renderSteps(steps) {
    var root = document.getElementById('first-steps');
    root.textContent = '';
    (steps || []).forEach(function (s) {
      var hasLink = s.url !== undefined || s.common || s.docs !== undefined || s.repo || s.pages || s.ref;
      var r = hasLink ? resolve(s) : {};
      var li = el('li', null, [s.text]);
      if (r.href) {
        li.appendChild(document.createTextNode(' '));
        li.appendChild(el('a', { href: r.href, text: 'Open' }));
      } else if (r.unset) {
        li.appendChild(document.createTextNode(' '));
        li.appendChild(el('span', { class: 'pill warn', text: r.unset }));
      }
      root.appendChild(li);
    });
  }

  function renderWhere(rows) {
    var root = document.getElementById('where');
    root.textContent = '';
    (rows || []).forEach(function (w) {
      var r = resolve(w);
      var fileCell = r.href ? el('a', { href: r.href }, [el('code', { text: w.file })]) : el('code', { text: w.file });
      root.appendChild(el('tr', null, [el('td', { text: w.change }), el('td', null, [fileCell])]));
    });
  }

  function personBlock(p, roleOverride) {
    if (!p) return null;
    var meta = [];
    if (p.ext) meta.push('Ext. ' + p.ext);
    if (p.office) meta.push(p.office);
    return el('div', { class: 'person' }, [
      el('span', { class: 'person-name', text: p.name }),
      el('span', { class: 'person-role', text: roleOverride || p.role || '' }),
      el('span', { class: 'person-meta' }, [
        p.email ? el('a', { href: 'mailto:' + p.email, text: p.email }) : null,
        meta.length ? ' · ' + meta.join(' · ') : null
      ])
    ]);
  }

  function renderContacts() {
    var root = document.getElementById('contacts');
    root.textContent = '';
    if (state.commonError) {
      root.appendChild(el('p', { class: 'muted', text: 'Shared contact data could not be loaded. See the team directory.' }));
      return;
    }
    var c = state.clusters;
    var director = state.people[c.default_validator];
    if (director) root.appendChild(personBlock(director));
    (c.administration || []).forEach(function (id) { root.appendChild(personBlock(state.people[id])); });

    var boxes = el('ul', { class: 'mailboxes' });
    (state.cfg.mailboxes || []).forEach(function (m) {
      var addr = get(state.common, m.common);
      if (!addr) return;
      boxes.appendChild(el('li', null, [el('a', { href: 'mailto:' + addr, text: addr }), el('span', { text: m.label })]));
    });
    if (boxes.children.length) root.appendChild(boxes);

    var a = state.common.address;
    if (a) {
      root.appendChild(el('p', { class: 'address', text: [a.line1, a.line2, a.city, a.country].filter(Boolean).join(', ') }));
    }
    root.appendChild(el('a', { class: 'side-more', href: join((state.cfg.sources || {}).docs_site, 'team/') },
      ['Full team directory', icon('arrow-up-right', 'arrow')]));
  }

  function renderClusters() {
    var root = document.getElementById('clusters');
    root.textContent = '';
    var list = (state.clusters && state.clusters.clusters) || [];
    if (!list.length) {
      root.appendChild(el('p', { class: 'muted', text: 'Cluster data could not be loaded.' }));
    } else {
      root.appendChild(el('ul', { class: 'cluster-list' }, list.map(function (cl) {
        var lead = cl.lead && state.people[cl.lead];
        return el('li', null, [
          el('span', { text: cl.name }),
          lead ? el('span', { class: 'lead', text: lead.name }) : el('span', { class: 'lead vacant', text: 'Lead to be named' })
        ]);
      })));
    }
    root.appendChild(el('a', { class: 'side-more', href: join((state.cfg.sources || {}).docs_site, 'orgchart/') },
      ['Full org chart', icon('arrow-up-right', 'arrow')]));
  }

  function renderFooter(build) {
    var s = state.cfg.sources || {};
    document.getElementById('edit-link').href = join(s.github_org, (s.this_repo || '') + '/edit/main/site/links.yaml');
    document.getElementById('common-link').href = join(s.github_org, 'ctp-common');
    var info = document.getElementById('build-info');
    if (build) {
      info.textContent = 'Deployed ' + build.deployed_at +
        ' · this repo ' + (build.landing_commit || '?') +
        ' · ctp-common ' + (build.common_commit || '?');
    } else {
      info.textContent = 'Local preview · shared data loaded from GitHub';
    }
  }

  function notice(msg) {
    var n = document.getElementById('notice');
    n.hidden = false;
    n.appendChild(el('p', { text: msg, style: 'margin:0 0 4px' }));
  }

  // ---------- filter ----------
  function setupFilter() {
    var input = document.getElementById('filter');
    function apply() {
      var terms = input.value.toLowerCase().split(/\s+/).filter(Boolean);
      var filtering = terms.length > 0;
      document.body.classList.toggle('is-filtering', filtering);
      var visible = 0;
      document.querySelectorAll('[data-search]').forEach(function (node) {
        var hay = node.getAttribute('data-search');
        var show = terms.every(function (t) { return hay.indexOf(t) !== -1; });
        node.hidden = !show;
        if (show) visible++;
      });
      document.querySelectorAll('[data-section]').forEach(function (sec) {
        sec.hidden = !sec.querySelector('li:not([hidden])');
      });
      var hl = document.getElementById('highlights').closest('section');
      hl.hidden = filtering && !document.querySelector('#highlights > :not([hidden])');
      document.getElementById('no-results').hidden = !(filtering && visible === 0);
    }
    input.addEventListener('input', apply);
    input.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') { input.value = ''; apply(); input.blur(); }
      if (e.key === 'Enter') {
        var hits = Array.prototype.filter.call(document.querySelectorAll('[data-search]'), function (n) { return !n.hidden; });
        var a = hits.length === 1 && (hits[0].matches('a') ? hits[0] : hits[0].querySelector('a'));
        if (a) window.location.href = a.href;
      }
    });
    document.addEventListener('keydown', function (e) {
      if (e.key === '/' && document.activeElement !== input && !/input|textarea/i.test(document.activeElement.tagName)) {
        e.preventDefault(); input.focus();
      }
    });
  }

  // ---------- boot ----------
  function indexIds(cfg) {
    var all = [].concat(cfg.highlights || []);
    (cfg.sections || []).forEach(function (s) { all = all.concat(s.links || []); });
    all.forEach(function (l) { if (l.id) state.byId[l.id] = l; });
  }

  function loadCommon(isDeployed) {
    var raw = (state.cfg.sources || {}).ctp_common_raw;
    return Promise.all(COMMON_FILES.map(function (f) {
      var urls = ['data/ctp-common/' + f];
      if (raw) urls.push(join(raw, f));
      return firstOk(urls);
    })).then(function (res) {
      if (isDeployed && res.some(function (r) { return r.url.indexOf('data/ctp-common/') !== 0; })) {
        notice('The server copy of ctp-common is missing, so shared data is being read from GitHub. Run the deploy script on the server to fix this.');
      }
      state.common = res[0].data;
      (res[1].data.people || []).forEach(function (p) { state.people[p.netid] = p; });
      state.clusters = res[2].data;
    }, function (err) {
      state.commonError = err;
      notice('Shared data from ctp-common could not be loaded (' + err.message + '). Links that depend on it are marked as unavailable.');
    });
  }

  function boot() {
    setupFilter();
    var buildP = fetch('build-info.json', { cache: 'no-cache' })
      .then(function (r) { return r.ok ? r.json() : null; })
      .catch(function () { return null; });

    fetchYaml('links.yaml').then(function (cfg) {
      state.cfg = cfg;
      indexIds(cfg);
      var page = cfg.page || {};
      if (page.title) { document.getElementById('page-title').textContent = page.title; document.title = page.title + ' · NYU Abu Dhabi'; }
      document.getElementById('page-intro').textContent = page.intro || '';
      return buildP.then(function (build) {
        renderFooter(build);
        return loadCommon(!!build);
      });
    }).then(function () {
      var cfg = state.cfg;
      renderHighlights(cfg.highlights);
      renderSections(cfg.sections);
      renderSteps(cfg.first_steps);
      renderWhere(cfg.where_to_edit);
      renderContacts();
      renderClusters();
    }).catch(function (err) {
      notice('links.yaml could not be loaded or parsed: ' + err.message);
      console.error(err);
    });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
