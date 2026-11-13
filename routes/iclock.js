// ════════════════════════════════════════════════════════════════
// Contrôle d'accès — dialogue avec les appareils ZKTeco (protocole ADMS / « Push »)
//   Réglage sur l'appareil : COMM → Configuration Serveur Cloud
//     Mode ADMS · nom de domaine activé · www.lescollinesfitness.com · HTTPS activé
//   Deux variantes du protocole sont gérées :
//   • « acc » (contrôle d'accès, Push 3.x — cas des SpeedFace-V3L) :
//       POST /iclock/registry?SN=…            enregistrement → RegistryCode
//       GET  /iclock/cdata?SN=…&options=all   réglages (registry=ok…)
//       GET|POST /iclock/push?SN=…            réglages
//       POST /iclock/cdata?SN=…&table=rtlog   passages en temps réel
//       POST /iclock/cdata?SN=…&table=tabledata&tablename=user|biodata   personnes / visages enregistrés
//       POST /iclock/querydata?SN=…&tablename=…   réponse à une demande de liste
//       GET  /iclock/rtdata?SN=…&type=time    heure du serveur
//   • « att » (pointage, Push 2.x) : cdata (ATTLOG, OPERLOG, BIODATA)
//   Commun : GET /iclock/getrequest (commandes en attente) · POST /iclock/devicecmd (résultats)
//   Toute la logique (qui est autorisé, file de commandes) est dans Supabase (scripts 43 et 44).
//   Variable Vercel nécessaire : SUPABASE_SERVICE_KEY (clé secrète de Supabase).
// ════════════════════════════════════════════════════════════════
const express = require('express');
const crypto  = require('crypto');
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
const corpsDe = req => typeof req.body === 'string' ? req.body : '';
const requeteDe = req => (req.method + ' ' + req.originalUrl).slice(0, 500);
const sansModeles = s => String(s || '').replace(/(Tmp|TMP|tmp|Content|content)=[^\t\r\n]{40,}/g, '$1=…');
const journal = (sn, req, corps, reponse) =>
  rpc('acces_journaliser', { p_sn: sn || null, p_requete: requeteDe(req), p_corps: corps ? sansModeles(corps).slice(0, 2000) : null, p_reponse: reponse ? sansModeles(reponse) : null })
    .catch(e => console.error('[iclock] journal', e.message));

// Protocole « contrôle d'accès » (Push 3.x) ?
const estAcc = req => /acc/i.test(String(req.query.DeviceType || req.query.devicetype || '')) || /^3/.test(String(req.query.pushver || ''));
const hash = (s, n) => crypto.createHash('md5').update('lescollines:' + s).digest('hex').slice(0, n).toUpperCase();
const codeRegistre = sn => hash(sn, 10);

// Réglages envoyés à un appareil « acc »
const optionsAcc = sn => [
  'registry=ok',
  `RegistryCode=${codeRegistre(sn)}`,
  'ServerVersion=3.1.2',
  'ServerName=ADMS',
  'PushProtVer=3.1.2',
  'ErrorDelay=30',
  'RequestDelay=15',
  'TransTimes=00:00;12:00',
  'TransInterval=1',
  'TransTables=User Transaction',
  'Realtime=1',
  `SessionID=${hash(sn + ':session', 32)}`,
  'TimeoutSec=10'
].join('\n') + '\n';

// Réglages envoyés à un appareil « att » (pointage)
const optionsAtt = (sn, st) => [
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

// Heure ZKTeco (secondes depuis 2000, mois de 31 jours), heure du Maroc (UTC+1)
function heureZk() {
  const d = new Date(Date.now() + 3600 * 1000);
  return ((d.getUTCFullYear() - 2000) * 12 * 31 + d.getUTCMonth() * 31 + d.getUTCDate() - 1) * 86400
    + d.getUTCHours() * 3600 + d.getUTCMinutes() * 60 + d.getUTCSeconds();
}

// « Clé=Valeur\tClé=Valeur » → objet (clés en minuscules)
function champs(s) {
  const o = {};
  String(s || '').split('\t').forEach(p => {
    const i = p.indexOf('=');
    if (i > 0) o[p.slice(0, i).trim().toLowerCase()] = p.slice(i + 1).trim();
  });
  return o;
}

// Ligne de modèle biométrique « acc », clés remises dans la forme attendue par les commandes
const CLES_BIODATA = ['Pin', 'No', 'Index', 'Valid', 'Duress', 'Type', 'MajorVer', 'MinorVer', 'Format', 'Tmp'];
const ligneBiodataAcc = f => 'biodata ' + CLES_BIODATA.map(k => `${k}=${f[k.toLowerCase()] ?? ''}`).join('\t');

// Contenu envoyé par l'appareil → liste pour Supabase
function analyser(table, corps) {
  const T = String(table || '').toUpperCase();
  const lignes = String(corps || '').split(/\r?\n/).map(l => l.replace(/\r$/, '')).filter(l => l.trim());
  const out = [];
  const okDate = s => /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}(:\d{2})?$/.test(String(s || '').trim());
  for (const l of lignes) {
    if (T === 'ATTLOG') {
      // PIN \t AAAA-MM-JJ HH:MM:SS \t état \t mode de vérification \t …
      const [pin, date_heure, statut, verification] = l.split('\t');
      if (pin && okDate(date_heure))
        out.push({ type: 'ATTLOG', pin: pin.trim(), date_heure: date_heure.trim(), statut: (statut || '').trim(), verification: (verification || '').trim() });
      continue;
    }
    if (T === 'RTLOG') {
      // time=… \t pin=… \t cardno=… \t eventaddr=… \t event=… \t inoutstatus=… \t verifytype=… …
      const f = champs(l.replace(/^rtlog\s+/i, ''));
      if (f.pin && f.pin !== '0' && okDate(f.time))
        out.push({ type: 'ATTLOG', pin: f.pin, date_heure: f.time, statut: f.event || '', verification: f.verifytype || '' });
      continue;
    }
    const esp = l.indexOf(' ');
    if (esp < 0) continue;
    const mot = l.slice(0, esp).toUpperCase(), reste = l.slice(esp + 1);
    const f = champs(reste);
    const pin = f.pin;
    if (!pin) continue;
    if (mot === 'USER') {
      // att : USER PIN=…\tName=…\tPri=…\tCard=…   acc : user uid=…\tcardno=…\tpin=…\tname=…\tprivilege=…
      const carte = String(f.card || f.cardno || '').replace(/[\[\]]/g, '');
      out.push({ type: 'USER', pin, nom: f.name || '', pri: f.pri || f.privilege || '0', carte: /^0*$/.test(carte) ? '' : carte });
    } else if (mot === 'BIODATA') {
      // Modèle biométrique (visage) : renvoyé tel quel aux autres appareils
      const acc = l.startsWith('biodata ');
      out.push({ type: 'BIO', pin, cle: `BIODATA:${f.type || ''}:${f.no || ''}:${f.index || ''}`, ligne: acc ? ligneBiodataAcc(f) : 'BIODATA ' + reste });
    } else if (mot === 'FACE') {
      out.push({ type: 'BIO', pin, cle: `FACE:${f.fid || ''}`, ligne: 'FACE ' + reste });
    } else if (mot === 'FP') {
      out.push({ type: 'BIO', pin, cle: `FP:${f.fid || ''}`, ligne: 'FINGERTMP ' + reste });
    }
    // OPLOG, USERPIC, BIOPHOTO… : ignorés (photos non conservées)
  }
  return out;
}

// ── Enregistrement (acc) ────────────────────────────────────────
router.post('/registry', async (req, res) => {
  const sn = snDe(req);
  if (!sn) return texte(res, 'ERROR');
  try {
    const st = await rpc('acces_connexion', { p_sn: sn, p_ip: ipDe(req), p_infos: corpsDe(req).slice(0, 1500), p_protocole: 'acc' });
    if (!st) return texte(res, 'UNKNOWN DEVICE', 403);
    const rep = `RegistryCode=${codeRegistre(sn)}`;
    await journal(sn, req, corpsDe(req), rep);
    texte(res, rep);
  } catch (e) {
    console.error('[iclock] registry', e.message);
    await journal(sn, req, null, 'ERREUR : ' + e.message);
    texte(res, 'ERROR', 500);
  }
});

// ── Premier contact / réglages ──────────────────────────────────
async function reglages(req, res, viaPush) {
  const sn = snDe(req);
  if (!sn) return texte(res, 'ERROR');
  const acc = viaPush || estAcc(req);
  try {
    const st = await rpc('acces_connexion', { p_sn: sn, p_ip: ipDe(req), p_infos: requeteDe(req), p_protocole: acc ? 'acc' : 'att' });
    if (!st) return texte(res, 'UNKNOWN DEVICE', 403);
    const rep = acc ? optionsAcc(sn) : optionsAtt(sn, st);
    await journal(sn, req, viaPush ? corpsDe(req) : null, rep);
    texte(res, rep);
  } catch (e) {
    console.error('[iclock] réglages', e.message);
    await journal(sn, req, null, 'ERREUR : ' + e.message);
    texte(res, 'ERROR', 500);
  }
}
router.get('/cdata', (req, res) => reglages(req, res, false));
router.all('/push', (req, res) => reglages(req, res, true));

// ── Données envoyées par l'appareil ─────────────────────────────
async function recevoir(req, res, table, reponseOk) {
  const sn = snDe(req);
  if (!sn) return texte(res, 'ERROR');
  const corps = corpsDe(req);
  try {
    const donnees = analyser(table, corps);
    const n = await rpc('acces_recevoir', { p_sn: sn, p_table: table, p_stamp: String(req.query.Stamp || req.query.stamp || ''), p_donnees: donnees });
    if (n === -1) return texte(res, 'UNKNOWN DEVICE', 403);
    const rep = reponseOk(corps);
    await journal(sn, req, corps, `${rep} (${donnees.length} lignes lues)`);
    texte(res, rep);
  } catch (e) {
    console.error('[iclock] données', e.message);
    await journal(sn, req, corps.slice(0, 1000), 'ERREUR : ' + e.message);
    // Erreur : l'appareil renverra les mêmes données plus tard
    texte(res, 'ERROR', 500);
  }
}
const nbLignes = corps => String(corps || '').split(/\r?\n/).filter(l => l.trim()).length;

router.post('/cdata', (req, res) => {
  const table = String(req.query.table || '').trim();
  if (/^tabledata$/i.test(table)) {
    // Personnes / visages enregistrés sur l'appareil : réponse « user=1 », « biodata=1 »…
    const nom = String(req.query.tablename || '').trim();
    return recevoir(req, res, nom, c => `${nom}=${req.query.count || nbLignes(c)}`);
  }
  if (/^(rtstate|options)$/i.test(table)) {
    // État des portes / paramètres : non conservés
    return texte(res, 'OK');
  }
  return recevoir(req, res, table, () => 'OK');
});

// Réponse à « DATA QUERY tablename=… »
router.post('/querydata', (req, res) => {
  const nom = String(req.query.tablename || '').trim();
  return recevoir(req, res, nom, c => `${nom}=${req.query.count || nbLignes(c)}`);
});

// Heure du serveur (acc)
router.get('/rtdata', async (req, res) => {
  if (String(req.query.type || '') === 'time') return texte(res, `DateTime=${heureZk()},ServerTZ=+0100`);
  texte(res, 'OK');
});

// ── Commandes en attente ────────────────────────────────────────
router.get('/getrequest', async (req, res) => {
  const sn = snDe(req);
  if (!sn) return texte(res, 'OK');
  try {
    const cmds = await rpc('acces_requete', { p_sn: sn, p_ip: ipDe(req), p_info: String(req.query.INFO || req.query.info || '') });
    if (cmds === null) return texte(res, 'UNKNOWN DEVICE', 403);
    if (cmds) await journal(sn, req, null, cmds);
    texte(res, cmds || 'OK');
  } catch (e) {
    console.error('[iclock] getrequest', e.message);
    await journal(sn, req, null, 'ERREUR : ' + e.message);
    texte(res, 'OK');
  }
});

// ── Résultats des commandes : « ID=12&Return=0&CMD=DATA » (une ligne par commande) ──
router.post('/devicecmd', async (req, res) => {
  const sn = snDe(req);
  const corps = corpsDe(req);
  try {
    const res_ = corps.split(/\r?\n/).filter(l => l.includes('ID=')).map(l => {
      const p = new URLSearchParams(l.trim());
      return { id: p.get('ID'), retour: p.get('Return') };
    }).filter(x => /^\d+$/.test(x.id || ''));
    if (sn && res_.length) await rpc('acces_resultats', { p_sn: sn, p_res: res_ });
    await journal(sn, req, corps, 'OK');
  } catch (e) {
    console.error('[iclock] devicecmd', e.message);
    await journal(sn, req, corps.slice(0, 1000), 'ERREUR : ' + e.message);
  }
  texte(res, 'OK');
});

router.get('/ping', (req, res) => texte(res, 'OK'));

// Autres adresses : notées dans le journal pour diagnostic
router.all('*', async (req, res) => {
  await journal(snDe(req), req, corpsDe(req), 'OK (adresse non gérée)');
  texte(res, 'OK');
});

router._analyser = analyser;   // pour les tests
module.exports = router;
