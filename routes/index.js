const express = require('express');
const router  = express.Router();
const fs      = require('fs');
const path    = require('path');

const CONFIG_PATH = path.join(__dirname, '../config/site.json');

function getSite() {
  return JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
}

router.get('/', (req, res) => {
  res.render('index', { site: getSite() });
});

// ── Sitemap XML ──
router.get('/sitemap.xml', (req, res) => {
  const domain = 'https://lescollinesfitness.com';
  const today = new Date().toISOString().split('T')[0];
  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>${domain}/</loc>
    <lastmod>${today}</lastmod>
    <changefreq>weekly</changefreq>
    <priority>1.0</priority>
  </url>
  <url>
    <loc>${domain}/#sports</loc>
    <lastmod>${today}</lastmod>
    <changefreq>weekly</changefreq>
    <priority>0.9</priority>
  </url>
  <url>
    <loc>${domain}/#pourquoi</loc>
    <lastmod>${today}</lastmod>
    <changefreq>monthly</changefreq>
    <priority>0.7</priority>
  </url>
  <url>
    <loc>${domain}/#contact</loc>
    <lastmod>${today}</lastmod>
    <changefreq>monthly</changefreq>
    <priority>0.8</priority>
  </url>
  <url>
    <loc>${domain}/#faq</loc>
    <lastmod>${today}</lastmod>
    <changefreq>monthly</changefreq>
    <priority>0.8</priority>
  </url>
  <url>
    <loc>${domain}/membre/login</loc>
    <lastmod>${today}</lastmod>
    <changefreq>monthly</changefreq>
    <priority>0.4</priority>
  </url>
</urlset>`;
  res.set('Content-Type', 'application/xml');
  res.send(xml);
});

module.exports = router;
