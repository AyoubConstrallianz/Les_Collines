const express    = require('express');
const nodemailer = require('nodemailer');
const router     = express.Router();

// Clés publiques Supabase (les mêmes que dans /management) — surchargeables par variables d'environnement
const SUPABASE_URL      = process.env.SUPABASE_URL      || 'https://darwktarjsaameqianyi.supabase.co';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || 'sb_publishable_ltLpJObbU2HXbbZbwA4dgg_sGFg5BAc';

// Le PDF arrive en base64 : limite plus large que le parseur JSON global
router.use(express.json({ limit: '3mb' }));

// ── Envoi d'un reçu de paiement par e-mail ──
// Le destinataire n'est jamais fourni par le navigateur : c'est l'e-mail de la fiche client,
// lu dans Supabase avec le jeton de l'utilisateur connecté (donc soumis à ses droits).
router.post('/envoyer-recu', async (req, res) => {
  try {
    const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    const { paiement_id, paiement_ids, pdf_base64 } = req.body || {};
    // Un reçu peut regrouper plusieurs paiements du même client (ex. inscription + assurance)
    const ids = [...new Set((Array.isArray(paiement_ids) ? paiement_ids : [paiement_id]).filter(Boolean).map(String))];
    if (!token) return res.status(401).json({ error: 'Non connecté' });
    if (!ids.length || ids.length > 20 || !pdf_base64) return res.status(400).json({ error: 'Paramètres manquants' });
    if (!ids.every(id => /^[0-9a-f-]{36}$/i.test(id))) return res.status(400).json({ error: 'Identifiant invalide' });

    if (!process.env.GMAIL_USER || !process.env.GMAIL_APP_PASSWORD) {
      return res.status(503).json({ error: "L'envoi d'e-mails n'est pas encore configuré (GMAIL_USER / GMAIL_APP_PASSWORD sur Vercel)." });
    }

    const r = await fetch(
      `${SUPABASE_URL}/rest/v1/paiements?id=in.(${ids.join(',')})&select=client_id,numero_recu,montant,date_paiement,clients(prenom,nom,email)&order=numero_recu`,
      { headers: { apikey: SUPABASE_ANON_KEY, Authorization: `Bearer ${token}` } }
    );
    if (r.status === 401) return res.status(401).json({ error: 'Session expirée, reconnectez-vous' });
    const rows = r.ok ? await r.json() : [];
    if (rows.length !== ids.length) return res.status(404).json({ error: 'Paiement introuvable ou accès refusé' });
    if (new Set(rows.map(x => x.client_id)).size !== 1) return res.status(400).json({ error: 'Paiements de clients différents' });
    const p = rows[0];
    const montantTotal = rows.reduce((a, x) => a + (parseFloat(x.montant) || 0), 0);
    const numeros = [...new Set(rows.map(x => x.numero_recu).filter(Boolean))].join(' / ');

    const client = p.clients || {};
    if (!client.email) return res.status(400).json({ error: "Ce client n'a pas d'adresse e-mail" });

    const pdf = Buffer.from(String(pdf_base64).replace(/^data:application\/pdf;base64,/, ''), 'base64');
    if (pdf.subarray(0, 4).toString() !== '%PDF') return res.status(400).json({ error: 'PDF invalide' });

    const numero = (numeros || 'recu').replace(/[\s/]+/g, '_');
    const transporter = nodemailer.createTransport({
      service: 'gmail',
      auth: { user: process.env.GMAIL_USER, pass: process.env.GMAIL_APP_PASSWORD }
    });
    await transporter.sendMail({
      from: `"Association Les Collines" <${process.env.GMAIL_USER}>`,
      to: client.email,
      subject: `Votre reçu de paiement ${numeros}`.trim(),
      text: `Bonjour ${client.prenom || ''},\n\n`
          + `Merci pour votre paiement de ${montantTotal} DH du ${p.date_paiement}.\n`
          + `Vous trouverez votre reçu en pièce jointe.\n\n`
          + `Sportivement,\nAssociation Les Collines\nRésidence Les Collines, Sidi Maarouf, Casablanca\n06 61 09 27 66 — 06 62 02 87 33`,
      attachments: [{ filename: `${numero}.pdf`, content: pdf, contentType: 'application/pdf' }]
    });

    res.json({ ok: true, to: client.email });
  } catch (e) {
    console.error('envoyer-recu', e);
    res.status(500).json({ error: "Échec de l'envoi : " + (e.message || 'erreur inconnue') });
  }
});

module.exports = router;
