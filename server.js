require('dotenv').config();
const express    = require('express');
const cookieSession = require('cookie-session');
const crypto     = require('crypto');
const path       = require('path');

const indexRouter  = require('./routes/index');
const adminRouter  = require('./routes/admin');
const memberRouter = require('./routes/member');
const apiRouter    = require('./routes/api');

const app  = express();
const PORT = process.env.PORT || 3000;
const PROD = process.env.NODE_ENV === 'production' || !!process.env.VERCEL;

// Vercel est derrière un proxy HTTPS : nécessaire pour les cookies « secure »
app.set('trust proxy', 1);

// ── View engine ──
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

// ── API (avant le parseur JSON global : accepte des PDF jusqu'à 3 Mo) ──
app.use('/api', apiRouter);

// ── Middleware ──
app.use(express.urlencoded({ extended: true }));
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));
// Alias de l'application de gestion (même page que /management/)
app.use('/gestion', express.static(path.join(__dirname, 'public', 'management')));

// ── Session : cookie signé (le contenu est vérifié, impossible à modifier côté navigateur).
// Pas de stockage en mémoire serveur : la connexion tient même quand Vercel change d'instance.
let secretSession = process.env.SESSION_SECRET;
if (!secretSession) {
  if (PROD) console.warn('⚠ SESSION_SECRET absent : ajoutez-le dans Vercel → Settings → Environment Variables.');
  // Secret aléatoire plutôt qu'un secret connu : sûr, mais les connexions ne survivent pas à un redémarrage
  secretSession = PROD ? crypto.randomBytes(32).toString('hex') : 'dev-local-uniquement';
}
app.use(cookieSession({
  name: 'lc_session',
  keys: [secretSession],
  maxAge: 1000 * 60 * 10,      // 10 minutes d'inactivité (renouvelé à chaque requête, voir ci-dessous)
  httpOnly: true,              // illisible par le JavaScript de la page
  sameSite: 'lax',             // non envoyé par les formulaires d'autres sites
  secure: PROD                 // HTTPS uniquement en production
}));
// Session glissante : chaque requête d'un utilisateur connecté renouvelle le cookie (au plus une fois par minute) ;
// sans activité pendant 10 minutes, le cookie expire et il faut se reconnecter.
// Le serveur vérifie aussi l'heure de la dernière activité : un ancien cookie renvoyé après coup est refusé.
app.use((req, res, next) => {
  if (req.session && (req.session.admin || req.session.member)) {
    const minute = Math.floor(Date.now() / 60000);
    if (req.session.vu && minute - req.session.vu >= 10) req.session = {};   // session expirée → déconnecté
    else req.session.vu = minute;
  }
  next();
});

// ── Routes ──
app.use('/', indexRouter);
app.use('/admin', adminRouter);
app.use('/membre', memberRouter);

// ── 404 ──
app.use((req, res) => {
  res.status(404).render('404', {});
});

// ── Start (local) / Export (Vercel) ──
if (require.main === module) {
  app.listen(PORT, () => {
    console.log('\n╔════════════════════════════════════════╗');
    console.log('║   Les Collines des Sports — Serveur    ║');
    console.log('╚════════════════════════════════════════╝');
    console.log(`\n  Site public : http://localhost:${PORT}`);
    console.log(`  Admin       : http://localhost:${PORT}/admin`);
    console.log(`  Adhérents   : http://localhost:${PORT}/membre/login`);
    console.log(`\n  Identifiants admin par défaut :`);
    console.log(`    Utilisateur : ${process.env.ADMIN_USER || 'admin'}`);
    console.log(`    Mot de passe : (voir fichier .env)\n`);
  });
}

module.exports = app;
