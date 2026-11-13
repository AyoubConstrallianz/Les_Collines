// ════════════════════════════════════════════════════════════════
// Contrôle d'accès — dialogue avec les appareils ZKTeco (protocole ADMS / « Push »)
//   Réglage sur l'appareil : COMM → Configuration Serveur Cloud
//     Mode ADMS · nom de domaine activé · www.lescollinesfitness.com · port 443 · HTTPS activé
//   L'appareil appelle régulièrement :
//     GET  /iclock/cdata?SN=…&options=all   premier contact → réglages
//     POST /iclock/cdata?SN=…&table=…       entrées (ATTLOG), personnes et visages (OPERLOG / BIODATA)
//     GET  /iclock/getrequest?SN=…          « avez-vous des commandes pour moi ? »
//     POST /iclock/devicecmd?SN=…           résultats des commandes
//   Toute la logique (qui est autorisé, file de commandes) est dans Supabase (script 43).
//   Variable Vercel nécessaire : SUPABASE_SERVICE_KEY (clé secrète « service_role » de Supabase).
// ════════════════════════════════════════════════════════════════
const express = require('express');
const router  = express.Router();

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://darwktarjsaameqianyi.supabase.co';
const cleServeur = () => process.env.SUPABASE_SERVICE_KEY || '';

// Les appareils envoient du texte brut (pas du JSON)
router.use(express.text({ type: () => true, limit: '10mb' }));

async function rpc(fn, args) {
  const cle = cleServeur();
  if (!cle) throw new Error('SUPABASE_SERVICE_KEY absente (Vercel → Settings → Environment Variables)');
  const headers = { apikey: cle, 'Content-Type': 'application/json' };
  // Ancienne clé (JWT) : aussi dans Authorization ; nouvelle clé « sb_secret_… » : apikey seul
  if (!cle.startsWith('sb_')) headers.Authorization = 'Bearer ' + cle;
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, { method: 'POST', headers, body: JSON.stringify(args) });
  const txt = await r.text();
  if (!r.ok) throw new Error(`${fn} → ${r.status} ${txt.slice(0, 300)}`);
  return txt ? JSON.parse(txt) : null;
}

const texte = (res, s, code = 200) => res.status(code).type('text/plain').send(s);
const ipDe  = req => String(req.headers['cf-connecting-ip'] || req.headers['x-forwarded-for'] || req.ip || '').split(',')[0].trim();
const snDe  = req => String(req.query.SN || req.query.sn || '').trim().slice(0, 40);
const requeteDe = req => (req.method + ' ' + req.originalUrl).slice(0, 500);
const journal = (sn, req, corps, reponse) =>
  rpc('acces_journaliser', { p_sn: sn || null, p_requete: requeteDe(req), p_corps: corps || null, p_reponse: reponse || null })
    .catch(e => console.error('[iclock] journal', e.message));

// « Clé=Valeur\tClé=Valeur » → objet (clés en minuscules)
function champs(s) {
  const o = {};
  String(s || '').split('\t').forEach(p => {
    const i = p.indexOf('=');
    if (i > 0) o[p.slice(0, i).trim().toLowerCase()] = p.slice(i + 1).trim();
  });
  return o;
}

// Contenu envoyé par l'appareil → liste pour Supabase
function analyser(table, corps) {
  const lignes = String(corps || '').split(/\r?\n/).map(l => l.replace(/\r$/, '')).filter(l => l.trim());
  const out = [];
  for (const l of lignes) {
    if (String(table).toUpperCase() === 'ATTLOG') {
      // PIN \t AAAA-MM-JJ HH:MM:SS \t état \t mode de vérification \t …
      const [pin, date_heure, statut, verification] = l.split('\t');
      if (pin && /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}(:\d{2})?$/.test((date_heure || '').trim()))
        out.push({ type: 'ATTLOG', pin: pin.trim(), date_heure: date_heure.trim(), statut: (statut || '').trim(), verification: (verification || '').trim() });
      continue;
    }
    const esp = l.indexOf(' ');
    if (esp < 0) continue;
    const mot = l.slice(0, esp).toUpperCase(), reste = l.slice(esp + 1);
    const f = champs(reste);
    const pin = f.pin;
    if (!pin) continue;
    if (mot === 'USER') {
      const carte = (f.card || '').replace(/[\[\]]/g, '');
      out.push({ type: 'USER', pin, nom: f.name || '', pri: f.pri || '0', carte: /^0*$/.test(carte) ? '' : carte });
    } else if (mot === 'BIODATA') {
      // Modèle biométrique (visage) : renvoyé tel quel aux autres appareils
      out.push({ type: 'BIO', pin, cle: `BIODATA:${f.type || ''}:${f.no || ''}:${f.index || ''}`, ligne: 'BIODATA ' + reste });
    } else if (mot === 'FACE') {
      out.push({ type: 'BIO', pin, cle: `FACE:${f.fid || ''}`, ligne: 'FACE ' + reste });
    } else if (mot === 'FP') {
      out.push({ type: 'BIO', pin, cle: `FP:${f.fid || ''}`, ligne: 'FINGERTMP ' + reste });
    }
    // OPLOG, USERPIC, BIOPHOTO… : ignorés (photos non conservées)
  }
  return out;
}

// ── Premier contact / envoi de données ──────────────────────────
router.get('/cdata', async (req, res) => {
  const sn = snDe(req);
  if (!sn) return texte(res, 'ERROR');
  try {
    const st = await rpc('acces_connexion', { p_sn: sn, p_ip: ipDe(req), p_infos: requeteDe(req) });
    if (!st) return texte(res, 'UNKNOWN DEVICE', 403);
    const rep = [
      `GET OPTION FROM: ${sn}`,
      `ATTLOGStamp=${st.attlog || 0}`,
      `OPERLOGStamp=${st.operlog || 0}`,
      'ATTPHOTOStamp=None',
      'ErrorDelay=30',
      'Delay=15',
      'TransTimes=00:00;12:00',
      'TransInterval=1',
      'TransFlag=TransData AttLog\tOpLog\tEnrollUser\tChgUser\tEnrollFP\tChgFP\tFACE\tBIODATA',
      'TimeZone=1',
      'Realtime=1',
      'Encrypt=None',
      'ServerVer=2.4.1',
      'PushProtoVer=2.4.1'
    ].join('\n') + '\n';
    await journal(sn, req, null, rep);
    texte(res, rep);
  } catch (e) {
    console.error('[iclock] cdata GET', e.message);
    texte(res, 'ERROR', 500);
  }
});

router.post('/cdata', async (req, res) => {
  const sn = snDe(req);
  if (!sn) return texte(res, 'ERROR');
  const table = String(req.query.table || '').trim();
  const corps = typeof req.body === 'string' ? req.body : '';
  try {
    const donnees = analyser(table, corps);
    const n = await rpc('acces_recevoir', { p_sn: sn, p_table: table, p_stamp: String(req.query.Stamp || req.query.stamp || ''), p_donnees: donnees });
    if (n === -1) return texte(res, 'UNKNOWN DEVICE', 403);
    // Le journal garde le début du contenu, sans les modèles biométriques
    await journal(sn, req, corps.replace(/(Tmp|TMP|Content)=[^\t\r\n]{40,}/g, '$1=…').slice(0, 2000), `OK (${donnees.length} lignes lues)`);
    texte(res, 'OK');
  } catch (e) {
    console.error('[iclock] cdata POST', e.message);
    // Erreur : l'appareil renverra les mêmes données plus tard
    texte(res, 'ERROR', 500);
  }
});

// ── Commandes en attente ────────────────────────────────────────
router.get('/getrequest', async (req, res) => {
  const sn = snDe(req);
  if (!sn) return texte(res, 'OK');
  try {
    const cmds = await rpc('acces_requete', { p_sn: sn, p_ip: ipDe(req), p_info: String(req.query.INFO || req.query.info || '') });
    if (cmds === null) return texte(res, 'UNKNOWN DEVICE', 403);
    if (cmds) await journal(sn, req, null, cmds.replace(/(Tmp|TMP)=[^\t\r\n]{40,}/g, '$1=…'));
    texte(res, cmds || 'OK');
  } catch (e) {
    console.error('[iclock] getrequest', e.message);
    texte(res, 'OK');
  }
});

// ── Résultats des commandes : « ID=12&Return=0&CMD=DATA » (une ligne par commande) ──
router.post('/devicecmd', async (req, res) => {
  const sn = snDe(req);
  const corps = typeof req.body === 'string' ? req.body : '';
  try {
    const res_ = corps.split(/\r?\n/).filter(l => l.includes('ID=')).map(l => {
      const p = new URLSearchParams(l.trim());
      return { id: p.get('ID'), retour: p.get('Return') };
    }).filter(x => /^\d+$/.test(x.id || ''));
    if (sn && res_.length) await rpc('acces_resultats', { p_sn: sn, p_res: res_ });
    await journal(sn, req, corps.slice(0, 2000), 'OK');
  } catch (e) {
    console.error('[iclock] devicecmd', e.message);
  }
  texte(res, 'OK');
});

router.get('/ping', (req, res) => texte(res, 'OK'));

// Autres adresses (versions plus récentes du protocole) : notées dans le journal pour diagnostic
router.all('*', async (req, res) => {
  const corps = typeof req.body === 'string' ? req.body : '';
  await journal(snDe(req), req, corps.slice(0, 2000), 'OK (adresse non gérée)');
  texte(res, 'OK');
});

router._analyser = analyser;   // pour les tests
module.exports = router;
