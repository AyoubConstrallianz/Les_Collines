/* ── Gestion des cookies ──
   - Cookies nécessaires (connexion à l'espace adhérent, mémorisation du choix) : toujours actifs.
   - Contenus externes (carte Google Maps, vidéos YouTube) : chargés seulement avec l'accord du visiteur.
   Le choix est gardé dans le cookie « lc_consent » jusqu'à la fermeture du navigateur (cookie de session)
   et peut être modifié à tout moment
   (lien « Gérer les cookies » ou tout élément portant l'attribut data-cookies-ouvrir). */
(function () {
  'use strict';
  var NOM = 'lc_consent', VERSION = 1;
  var memoire = null;   // choix de la page en cours (si le navigateur interdit les cookies)

  function lire() {
    var m = null;
    try { m = document.cookie.match(/(?:^|;\s*)lc_consent=([^;]*)/); } catch (e) {}   // certains navigateurs intégrés interdisent les cookies
    if (!m) return memoire;
    try { var c = JSON.parse(decodeURIComponent(m[1])); return c && c.v === VERSION ? c : memoire; } catch (e) { return memoire; }
  }
  function ecrire(externes) {
    var c = { v: VERSION, externes: !!externes, date: new Date().toISOString().slice(0, 10) };
    memoire = c;
    try {
      document.cookie = NOM + '=' + encodeURIComponent(JSON.stringify(c)) + '; Path=/; SameSite=Lax'
        + (location.protocol === 'https:' ? '; Secure' : '');
    } catch (e) {}
    return c;
  }

  // ── Contenus externes : l'adresse réelle est dans data-consent-src, chargée seulement après accord
  function activerExternes() {
    document.querySelectorAll('[data-consent-src]').forEach(function (el) {
      if (!el.getAttribute('src')) el.setAttribute('src', el.getAttribute('data-consent-src'));
    });
    document.querySelectorAll('.consent-bloc').forEach(function (b) { b.classList.add('consent-ok'); });
  }

  function choisir(externes) {
    var avant = lire();
    ecrire(externes);
    fermerBandeau(); fermerPanneau();
    if (externes) activerExternes();
    else if (avant && avant.externes && document.querySelector('[data-consent-src][src]')) location.reload();   // retire les contenus déjà chargés
    document.dispatchEvent(new CustomEvent('lc:consentement', { detail: lire() }));
  }

  // ── Styles (injectés : un seul fichier à inclure dans chaque page)
  var css = ''
    + '.cc-bandeau{position:fixed;z-index:1000;left:50%;bottom:16px;transform:translateX(-50%);width:min(760px,calc(100vw - 32px));background:#111;border:1px solid #2a2a2a;border-top:3px solid #c8f700;border-radius:8px;box-shadow:0 20px 50px -10px rgba(0,0,0,.75);padding:1.1rem 1.25rem;color:#fff;font-family:Barlow,system-ui,sans-serif;font-size:.9rem;line-height:1.55}'
    + '.cc-titre{font-family:"Barlow Condensed",system-ui,sans-serif;font-weight:800;text-transform:uppercase;letter-spacing:.06em;font-size:1.05rem;margin:0 0 .35rem;color:#c8f700}'
    + '.cc-texte{color:#bbb;margin:0}.cc-texte a,.cc-panneau a{color:#fff;text-decoration:underline}'
    + '.cc-actions{display:flex;flex-wrap:wrap;gap:.6rem;margin-top:.9rem}'
    + '.cc-btn{font-family:"Barlow Condensed",system-ui,sans-serif;font-weight:700;letter-spacing:.08em;text-transform:uppercase;font-size:.85rem;padding:.65rem 1.1rem;border-radius:4px;border:1px solid #555;background:transparent;color:#fff;cursor:pointer;flex:1 1 150px}'
    + '.cc-btn:hover{border-color:#c8f700;color:#c8f700}.cc-btn:focus-visible{outline:2px solid #c8f700;outline-offset:2px}'
    + '.cc-btn-p{background:#c8f700;color:#080808;border-color:#c8f700}.cc-btn-p:hover{background:#d9ff3d;color:#080808}'
    + '.cc-lien{background:none;border:0;padding:0;color:#bbb;font:inherit;text-decoration:underline;cursor:pointer}.cc-lien:hover{color:#c8f700}'
    + '.cc-fond{position:fixed;inset:0;z-index:1001;background:rgba(0,0,0,.7);display:flex;align-items:center;justify-content:center;padding:16px}'
    + '.cc-panneau{background:#111;border:1px solid #2a2a2a;border-top:3px solid #c8f700;border-radius:8px;width:min(560px,100%);max-height:calc(100vh - 32px);overflow:auto;padding:1.4rem;color:#fff;font-family:Barlow,system-ui,sans-serif;font-size:.9rem;line-height:1.55}'
    + '.cc-ligne{display:flex;gap:1rem;align-items:flex-start;justify-content:space-between;padding:1rem 0;border-top:1px solid #222}'
    + '.cc-ligne h3{font-family:"Barlow Condensed",system-ui,sans-serif;font-size:1rem;font-weight:700;text-transform:uppercase;letter-spacing:.05em;margin:0}'
    + '.cc-ligne p{color:#999;font-size:.85rem;margin:.2rem 0 0}'
    + '.cc-toujours{font-size:.7rem;color:#c8f700;font-weight:700;text-transform:uppercase;letter-spacing:.08em;white-space:nowrap;padding-top:.2rem}'
    + '.cc-switch{position:relative;width:46px;height:26px;flex-shrink:0;margin-top:.1rem}'
    + '.cc-switch input{position:absolute;inset:0;width:100%;height:100%;margin:0;opacity:0;cursor:pointer}'
    + '.cc-switch span{position:absolute;inset:0;border-radius:13px;background:#333;transition:background .2s;pointer-events:none}'
    + '.cc-switch span::after{content:"";position:absolute;top:3px;left:3px;width:20px;height:20px;border-radius:50%;background:#fff;transition:transform .2s}'
    + '.cc-switch input:checked+span{background:#c8f700}.cc-switch input:checked+span::after{transform:translateX(20px);background:#080808}'
    + '.cc-switch input:focus-visible+span{outline:2px solid #c8f700;outline-offset:2px}'
    + '.consent-bloc{position:relative}.consent-bloc iframe:not([src]){display:none}.consent-bloc.consent-ok .consent-placeholder{display:none}'
    + '.consent-placeholder{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:.75rem;text-align:center;padding:1.5rem;min-height:250px;background:repeating-linear-gradient(45deg,#111 0 10px,#0d0d0d 10px 20px);color:#bbb;font-size:.88rem;line-height:1.5}'
    + '.consent-placeholder p{margin:0;max-width:420px}.consent-placeholder a{color:#fff;text-decoration:underline;font-size:.82rem}'
    + '.consent-placeholder .cc-btn{flex:0 0 auto}'
    + '@media (max-width:520px){.cc-bandeau{bottom:10px;padding:1rem;font-size:.85rem}.cc-btn{flex-basis:100%}}';
  var st = document.createElement('style'); st.textContent = css; document.head.appendChild(st);

  // ── Bandeau (premier passage)
  var bandeau = null, fond = null, dernierFocus = null;
  function ouvrirBandeau() {
    if (bandeau) return;
    bandeau = document.createElement('div');
    bandeau.className = 'cc-bandeau';
    bandeau.setAttribute('role', 'region');
    bandeau.setAttribute('aria-label', 'Gestion des cookies');
    bandeau.innerHTML = '<p class="cc-titre">Cookies</p>'
      + '<p class="cc-texte">Ce site utilise des cookies nécessaires à son fonctionnement (connexion à l\'espace adhérent). '
      + 'Avec votre accord, il affiche aussi des contenus externes (carte Google Maps, vidéos YouTube) qui déposent leurs propres cookies. '
      + 'Aucun cookie publicitaire ni de mesure d\'audience. <a href="/cookies">En savoir plus</a></p>'
      + '<div class="cc-actions">'
      + '<button type="button" class="cc-btn" data-cc="refuser">Tout refuser</button>'
      + '<button type="button" class="cc-btn" data-cc="personnaliser">Personnaliser</button>'
      + '<button type="button" class="cc-btn cc-btn-p" data-cc="accepter">Tout accepter</button>'
      + '</div>';
    document.body.appendChild(bandeau);
  }
  function fermerBandeau() { if (bandeau) { bandeau.remove(); bandeau = null; } }

  // ── Panneau de choix détaillé
  function ouvrirPanneau() {
    fermerPanneau();
    var c = lire();
    dernierFocus = document.activeElement;
    fond = document.createElement('div');
    fond.className = 'cc-fond';
    fond.innerHTML = '<div class="cc-panneau" role="dialog" aria-modal="true" aria-labelledby="cc-titre-panneau">'
      + '<p class="cc-titre" id="cc-titre-panneau">Gérer mes cookies</p>'
      + '<p class="cc-texte" style="margin-bottom:.6rem">Choisissez les cookies que vous acceptez. Vous pouvez changer d\'avis à tout moment avec le lien « Gérer les cookies » en bas de page. <a href="/cookies">Politique de cookies</a></p>'
      + '<div class="cc-ligne"><div><h3>Nécessaires</h3><p>Connexion à l\'espace adhérent (expire après 10 minutes d\'inactivité) et mémorisation de votre choix. Indispensables au site.</p></div><span class="cc-toujours">Toujours actifs</span></div>'
      + '<div class="cc-ligne"><div><h3><label for="cc-externes">Contenus externes</label></h3><p>Carte Google Maps (page Contact) et vidéos YouTube (espace adhérent). Google peut déposer ses propres cookies.</p></div>'
      + '<span class="cc-switch"><input type="checkbox" id="cc-externes"' + (c && c.externes ? ' checked' : '') + '><span></span></span></div>'
      + '<div class="cc-actions">'
      + '<button type="button" class="cc-btn" data-cc="refuser">Tout refuser</button>'
      + '<button type="button" class="cc-btn" data-cc="enregistrer">Enregistrer mes choix</button>'
      + '<button type="button" class="cc-btn cc-btn-p" data-cc="accepter">Tout accepter</button>'
      + '</div></div>';
    fond.addEventListener('mousedown', function (e) { if (e.target === fond && lire()) fermerPanneau(); });
    document.body.appendChild(fond);
    var premier = fond.querySelector('#cc-externes'); if (premier) premier.focus();
  }
  function fermerPanneau() {
    if (!fond) return;
    fond.remove(); fond = null;
    if (!lire()) ouvrirBandeau();   // aucun choix encore : le bandeau reste proposé
    if (dernierFocus && dernierFocus.focus) try { dernierFocus.focus(); } catch (e) {}
  }

  // ── Actions
  document.addEventListener('click', function (e) {
    var cible = e.target.closest ? e.target.closest('[data-cc],[data-cookies-ouvrir],.consent-autoriser') : null;
    if (!cible) return;
    if (cible.hasAttribute('data-cookies-ouvrir')) { e.preventDefault(); fermerBandeau(); ouvrirPanneau(); return; }
    if (cible.classList.contains('consent-autoriser')) { e.preventDefault(); choisir(true); return; }
    var a = cible.getAttribute('data-cc');
    if (a === 'accepter') choisir(true);
    else if (a === 'refuser') choisir(false);
    else if (a === 'personnaliser') { fermerBandeau(); ouvrirPanneau(); }
    else if (a === 'enregistrer') choisir(!!(fond && fond.querySelector('#cc-externes').checked));
  });
  document.addEventListener('keydown', function (e) {
    if (!fond) return;
    if (e.key === 'Escape') { fermerPanneau(); return; }
    if (e.key === 'Tab') {   // garde le focus dans le panneau
      var f = fond.querySelectorAll('button, input, a[href]'), p = f[0], d = f[f.length - 1];
      if (e.shiftKey && document.activeElement === p) { e.preventDefault(); d.focus(); }
      else if (!e.shiftKey && document.activeElement === d) { e.preventDefault(); p.focus(); }
    }
  });

  function demarrer() {
    var c = lire();
    if (!c) ouvrirBandeau();
    else if (c.externes) activerExternes();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', demarrer); else demarrer();

  window.lcCookies = { ouvrir: ouvrirPanneau, consentement: lire };
})();
