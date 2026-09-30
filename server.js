require('dotenv').config();
const express    = require('express');
const session    = require('express-session');
const path       = require('path');

const indexRouter  = require('./routes/index');
const adminRouter  = require('./routes/admin');
const memberRouter = require('./routes/member');

const app  = express();
const PORT = process.env.PORT || 3000;

// ── View engine ──
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

// ── Middleware ──
app.use(express.urlencoded({ extended: true }));
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

app.use(session({
  secret: process.env.SESSION_SECRET || 'lescollines_secret_key',
  resave: false,
  saveUninitialized: false,
  cookie: { maxAge: 1000 * 60 * 60 * 8 } // 8 heures
}));

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
