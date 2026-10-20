const express    = require('express');
const router     = express.Router();
const fs         = require('fs');
const path       = require('path');
const bcrypt     = require('bcryptjs');
const authMember = require('../middleware/authMember');

const MEMBERS_PATH = path.join(__dirname, '../data/members.json');
const CONTENT_PATH = path.join(__dirname, '../data/content.json');

function getMembers() { return JSON.parse(fs.readFileSync(MEMBERS_PATH, 'utf8')); }
function getContent()  { return JSON.parse(fs.readFileSync(CONTENT_PATH,  'utf8')); }

// ── Login ──
router.get('/login', (req, res) => {
  if (req.session.member) return res.redirect('/membre/dashboard');
  res.render('membre/login', { error: null });
});

router.post('/login', async (req, res) => {
  const { email, password } = req.body;
  const members = getMembers();
  const member  = members.find(m => m.email.toLowerCase() === email.toLowerCase() && m.active);

  if (member && await bcrypt.compare(password, member.password)) {
    req.session.member = { id: member.id, name: member.name, email: member.email };
    const dest = req.session.returnTo || '/membre/dashboard';
    delete req.session.returnTo;
    return res.redirect(dest);
  }
  res.render('membre/login', { error: 'Email ou mot de passe incorrect.' });
});

router.get('/logout', (req, res) => {
  delete req.session.member;
  res.redirect('/membre/login');
});

// ── Dashboard ──
router.get('/dashboard', authMember, (req, res) => {
  const content  = getContent();
  const videos   = content.filter(c => c.type === 'video');
  const programs = content.filter(c => c.type === 'programme');
  res.render('membre/dashboard', {
    member: req.session.member,
    videos,
    programs
  });
});

// ── Vidéo ──
router.get('/video/:id', authMember, (req, res) => {
  const content = getContent();
  const video   = content.find(c => c.id === req.params.id && c.type === 'video');
  if (!video) return res.redirect('/membre/dashboard');
  res.render('membre/video', { member: req.session.member, video });
});

// ── Programme ──
router.get('/programme/:id', authMember, (req, res) => {
  const content   = getContent();
  const programme = content.find(c => c.id === req.params.id && c.type === 'programme');
  if (!programme) return res.redirect('/membre/dashboard');
  res.render('membre/programme', { member: req.session.member, programme });
});

module.exports = router;
