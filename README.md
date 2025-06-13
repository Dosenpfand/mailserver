# MAILSERVER

Container configuration for a mail server setup.

## Services

* Mail server
* WireGuard VPN server
* Hosting of matheworkout.at

## Configuration

### matheworkout.env

```
FLASK_SECRET_KEY=
FLASK_SQLALCHEMY_DATABASE_URI=
FLASK_RECAPTCHA_PUBLIC_KEY=
FLASK_RECAPTCHA_PRIVATE_KEY=
FLASK_MAIL_SERVER=
FLASK_MAIL_PORT=
FLASK_MAIL_USE_TLS=
FLASK_MAIL_USERNAME=
FLASK_MAIL_PASSWORD=
FLASK_MAIL_DEFAULT_SENDER=
POSTGRES_PASSWORD=
POSTGRES_DB=
POSTGRES_USER=
SENTRY_DSN=
SENTRY_TRACES_SAMPLE_RATE=

```

### backup.env

```
RESTIC_REPOSITORY=
RESTIC_PASSWORD=
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
GOMAXPROCS=1
HEALTHCHECKS_URL=
EMAIL_TO=
EMAIL_FROM=
SMTP_SERVER=
SMTP_PORT=
SMTP_USER=
SMTP_PASSWORD=
SMTP_USE_TLS=
```

### wireguard.env

```
WG_HOST=
PASSWORD_HASH= # https://github.com/wg-easy/wg-easy/blob/v14/How_to_generate_an_bcrypt_hash.md
```

### stalwart config.toml

```
certificate.default.cert = "%{file:/data/certs/mail.zug.lol/cert.pem}%"
certificate.default.default = true
certificate.default.private-key = "%{file:/data/certs/mail.zug.lol/key.pem}%"
certificate.mail.eswardlicht.org.cert = "%{file:/data/certs/mail.eswardlicht.org/cert.pem}%"
certificate.mail.eswardlicht.org.private-key = "%{file:/data/certs/mail.eswardlicht.org/key.pem}%"
```
