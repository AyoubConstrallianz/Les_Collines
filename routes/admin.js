const express = require('express');
const router  = express.Router();
const fs      = require('fs');
const path    = require('path');
const multer  = require('multer');
const bcrypt  = require('bcryptjs');
const crypto  = require('crypto');
const auth    = require('../middleware/auth');

const CONFIG_PATH   = path.join(__dirname, '../config/site.json');
const MEMBERS_PATH  = path.join(__dirname, '../data/members.json');
const CONTENT_PATH  = path.join(__dirname, '../data/content.json');
const UPLOADS_DIR   = path.join(__dirname, '../public/uploads');

// ── Helpers ──
const getSite     = () => JSON.parse(fs.readFileSync(CONFIG_PATH,  'utf8'));
const saveSite    = d  => fs.writeFileSync(CONFIG_PATH,  JSON.stringify(d, null, 2), 'utf8');
const getMembers  = () => JSON.parse(fs.readFileSync(MEMBERS_PATH, 'utf8'));
const saveMembers = d  => fs.writeFileSync(MEMBERS_PATH, JSON.stringify(d, null, 2), 'utf8');
const getContent  = () => JSON.parse(fs.readFileSync(CONTENT_PATH, 'utf8'));
const saveContent = d  => fs.writeFileSync(CONTENT_PATH, JSON.stringify(d, null, 2), 'utf8');
const newId       = () => crypto.randomUUID();

// ── Multer: logo ──
const logoStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = path.join(UPLOADS_DIR);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => cb(null, 'logo' + path.extname(file.originalname).toLowerCase())
});
const uploadLogo = multer({
  storage: logoStorage,
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (req, file, cb) => file.mimetype.startsWith('image/') ? cb(null, true) : cb(new Error('Image uniquement'))
});

// ── Multer: vidéo ──
const videoStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = path.join(UPLOADS_DIR, 'videos');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => cb(null, Date.now() + '-' + file.originalname.replace(/\s+/g, '_'))
});
const uploadVideo = multer({
  storage: videoStorage,
  limits: { fileSize: 2 * 1024 * 1024 * 1024 }, // 2GB
  fileFilter: (req, file, cb) => file.mimetype.startsWith('video/') ? cb(null, true) : cb(new Error('Vidéo uniquement'))
});

// ── Multer: programme ──
const progStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = path.join(UPLOADS_DIR, 'programmes');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => cb(null, Date.now() + '-' + file.originalname.replace(/\s+/g, '_'))
});
const uploadProg = multer({
  storage: progStorage,
  limits: { fileSize: 100 * 1024 * 1024 }, // 100MB
  fileFilter: (req, file, cb) => {
    const allowed = ['application/pdf','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document','image/jpeg','image/png'];
    allowed.includes(file.mimetype) ? cb(null, true) : cb(new Error('Format non supporté'));
  }
});

// ── YouTube helper ──
function getYouTubeId(url) {
  if (!url) return null;
  const regex = /(?:youtube\.com\/(?:[^/]+\/.+\/|(?:v|e(?:mbed)?)\/|.*[?&]v=)|youtu\.be\/)([^"&?/\s]{11})/;
  const match = url.match(regex);
  return match ? match[1] : null;
}

// ════════════════════════════════════════════════
// AUTH
// ════════════════════════════════════════════════
router.get('/', (req, res) => {
  if (req.session.admin) return res.redirect('/admin/dashboard');
  res.redirect('/admin/login');
});

router.get('/login', (req, res) => {
  if (req.session.admin) return res.redirect('/admin/dashboard');
  res.render('admin/login', { error: null });
});

router.post('/login', (req, res) => {
  const { username, password } = req.body;
  if (username === process.env.ADMIN_USER && password === process.env.ADMIN_PASS) {
    req.session.admin = true;
    return res.redirect('/admin/dashboard');
  }
  res.render('admin/login', { error: 'Identifiant ou mot de passe incorrect.' });
});

router.get('/logout', (req, res) => {
  req.session.destroy(() => res.redirect('/admin/login'));
});

// ════════════════════════════════════════════════
// DASHBOARD (site settings)
// ════════════════════════════════════════════════
router.get('/dashboard', auth, (req, res) => {
  res.render('admin/dashboard', { site: getSite(), success: req.query.success || null });
});

router.post('/update-contact', auth, (req, res) => {
  const site = getSite();
  site.phones  = [req.body.phone1, req.body.phone2].filter(p => p && p.trim());
  site.email   = req.body.email   || site.email;
  site.address = req.body.address || site.address;
  saveSite(site);
  res.redirect('/admin/dashboard?success=contact');
});

router.post('/update-social', auth, (req, res) => {
  const site = getSite();
  site.social = { instagram: req.body.instagram || '', snapchat: req.body.snapchat || '', tiktok: req.body.tiktok || '' };
  saveSite(site);
  res.redirect('/admin/dashboard?success=social');
});

router.post('/update-logo', auth, uploadLogo.single('logo'), (req, res) => {
  if (req.file) { const site = getSite(); site.logo = '/uploads/' + req.file.filename; saveSite(site); }
  res.redirect('/admin/dashboard?success=logo');
});

router.post('/remove-logo', auth, (req, res) => {
  const site = getSite();
  if (site.logo) { const fp = path.join(__dirname, '../public', site.logo); if (fs.existsSync(fp)) fs.unlinkSync(fp); }
  site.logo = null; saveSite(site);
  res.redirect('/admin/dashboard?success=logo');
});

router.post('/update-services', auth, (req, res) => {
  const site = getSite();
  site.services = (req.body.services || '').split('\n').map(s => s.trim()).filter(Boolean);
  saveSite(site);
  res.redirect('/admin/dashboard?success=services');
});

router.post('/update-sports', auth, (req, res) => {
  const site = getSite();
  const parse = v => (v || '').split('\n').map(s => s.trim()).filter(Boolean);
  site.sports = { martial: parse(req.body.martial), fitness: parse(req.body.fitness), wellbeing: parse(req.body.wellbeing) };
  saveSite(site);
  res.redirect('/admin/dashboard?success=sports');
});

// ════════════════════════════════════════════════
// ADHÉRENTS
// ════════════════════════════════════════════════
router.get('/adherents', auth, (req, res) => {
  res.render('admin/adherents', {
    members: getMembers(),
    success: req.query.success || null,
    error:   req.query.error   || null
  });
});

router.post('/adherents/create', auth, async (req, res) => {
  const { name, email, password } = req.body;
  const members = getMembers();

  if (members.find(m => m.email.toLowerCase() === email.toLowerCase())) {
    return res.redirect('/admin/adherents?error=email_exists');
  }

  const hashed = await bcrypt.hash(password, 10);
  members.push({
    id:        newId(),
    name:      name.trim(),
    email:     email.trim().toLowerCase(),
    password:  hashed,
    active:    true,
    createdAt: new Date().toISOString()
  });
  saveMembers(members);
  res.redirect('/admin/adherents?success=created');
});

router.post('/adherents/toggle/:id', auth, (req, res) => {
  const members = getMembers();
  const m = members.find(m => m.id === req.params.id);
  if (m) { m.active = !m.active; saveMembers(members); }
  res.redirect('/admin/adherents?success=toggled');
});

router.post('/adherents/reset-pass/:id', auth, async (req, res) => {
  const { newPassword } = req.body;
  const members = getMembers();
  const m = members.find(m => m.id === req.params.id);
  if (m && newPassword) { m.password = await bcrypt.hash(newPassword, 10); saveMembers(members); }
  res.redirect('/admin/adherents?success=password');
});

router.post('/adherents/delete/:id', auth, (req, res) => {
  const members = getMembers().filter(m => m.id !== req.params.id);
  saveMembers(members);
  res.redirect('/admin/adherents?success=deleted');
});

// ════════════════════════════════════════════════
// CONTENU (vidéos & programmes)
// ════════════════════════════════════════════════
router.get('/contenu', auth, (req, res) => {
  const content = getContent();
  res.render('admin/contenu', {
    videos:    content.filter(c => c.type === 'video'),
    programs:  content.filter(c => c.type === 'programme'),
    success:   req.query.success || null,
    error:     req.query.error   || null
  });
});

// Ajouter une vidéo (URL YouTube OU fichier)
router.post('/contenu/add-video', auth, (req, res, next) => {
  // Si URL YouTube → pas d'upload
  if (req.body && req.body.youtubeUrl) return next('route');
  uploadVideo.single('videoFile')(req, res, next);
}, (req, res) => {
  const content  = getContent();
  const ytId     = getYouTubeId(req.body.youtubeUrl);
  const fileUrl  = req.file ? '/uploads/videos/' + req.file.filename : null;

  if (!ytId && !fileUrl) return res.redirect('/admin/contenu?error=no_source');

  content.push({
    id:          newId(),
    type:        'video',
    title:       (req.body.title || 'Vidéo sans titre').trim(),
    description: (req.body.description || '').trim(),
    category:    (req.body.category || 'Général').trim(),
    youtubeId:   ytId || null,
    file:        fileUrl,
    createdAt:   new Date().toISOString()
  });
  saveContent(content);
  res.redirect('/admin/contenu?success=video');
});

// Route alternative si seulement URL
router.post('/contenu/add-video', auth, (req, res) => {
  const content = getContent();
  const ytId    = getYouTubeId(req.body.youtubeUrl);
  if (!ytId) return res.redirect('/admin/contenu?error=invalid_url');

  content.push({
    id:          newId(),
    type:        'video',
    title:       (req.body.title || 'Vidéo sans titre').trim(),
    description: (req.body.description || '').trim(),
    category:    (req.body.category || 'Général').trim(),
    youtubeId:   ytId,
    file:        null,
    createdAt:   new Date().toISOString()
  });
  saveContent(content);
  res.redirect('/admin/contenu?success=video');
});

// Ajouter un programme
router.post('/contenu/add-programme', auth, uploadProg.single('programFile'), (req, res) => {
  const content = getContent();
  const fileUrl = req.file ? '/uploads/programmes/' + req.file.filename : null;
  if (!fileUrl) return res.redirect('/admin/contenu?error=no_file');

  content.push({
    id:          newId(),
    type:        'programme',
    title:       (req.body.title || 'Programme sans titre').trim(),
    description: (req.body.description || '').trim(),
    category:    (req.body.category || 'Général').trim(),
    file:        fileUrl,
    fileExt:     path.extname(req.file.originalname).toLowerCase(),
    createdAt:   new Date().toISOString()
  });
  saveContent(content);
  res.redirect('/admin/contenu?success=programme');
});

// Supprimer un contenu
router.post('/contenu/delete/:id', auth, (req, res) => {
  const content = getContent();
  const item    = content.find(c => c.id === req.params.id);
  if (item && item.file) {
    const fp = path.join(__dirname, '../public', item.file);
    if (fs.existsSync(fp)) fs.unlinkSync(fp);
  }
  saveContent(content.filter(c => c.id !== req.params.id));
  res.redirect('/admin/contenu?success=deleted');
});

module.exports = router;
