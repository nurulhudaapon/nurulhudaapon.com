-- Salted hash of CF-Connecting-IP, used to cap how much one sender can submit.
ALTER TABLE questions ADD COLUMN ip_hash TEXT;
ALTER TABLE bookings ADD COLUMN ip_hash TEXT;

-- /ask no longer has its own admin mode, /admin sits behind Cloudflare Access.
DELETE FROM credentials WHERE cat = 'admin';
