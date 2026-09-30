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

module.exports = router;
