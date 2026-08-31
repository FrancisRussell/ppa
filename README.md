# [Francis Russell's PPA](https://francisrussell.github.io/ppa)

Personal APT repository for Debian and Ubuntu (amd64 and arm64).

## Supported distributions (subject to change)

- Debian Trixie.
- Ubuntu Noble (24.04 LTS).

## Packages (subject to change)

- **encspot** — Console tool for detecting the encoder used to produce an MP3 file.
- **forgejo** — Self-hosted lightweight software forge.
- **fsv** — 3D filesystem visualizer.
- **lldap** — Lightweight LDAP server with a web UI. (Binary only — source packages not available.)
- **postfix-ratelimitd** — Postfix SMTP access policy daemon that rate-limits recipients per SASL username. (Binary only — source packages not available.)
- **pwsafe** — Command-line password safe compatible with PasswordSafe databases.

## Adding this repository

Download and install the signing key:

```sh
curl -fsSL https://francisrussell.github.io/ppa/KEY.asc \
  | sudo tee /etc/apt/keyrings/francis-russell-ppa.asc > /dev/null
sudo chmod 644 /etc/apt/keyrings/francis-russell-ppa.asc
```

Add the repository:

```sh
CODENAME=$(lsb_release -cs)
sudo tee /etc/apt/sources.list.d/francis-russell-ppa.sources > /dev/null <<EOF
Types: deb deb-src
URIs: https://francisrussell.github.io/ppa
Suites: $CODENAME
Components: main
Architectures: amd64 arm64
Signed-By: /etc/apt/keyrings/francis-russell-ppa.asc
EOF
sudo chmod 644 /etc/apt/sources.list.d/francis-russell-ppa.sources
```
