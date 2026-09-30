module.exports = function requireMember(req, res, next) {
  if (req.session && req.session.member) return next();
  req.session.returnTo = req.originalUrl;
  res.redirect('/membre/login');
};
