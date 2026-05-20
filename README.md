# Francis Russell's PPA

Personal APT repository for Debian and Ubuntu (amd64).

Supported distributions:

- Debian Trixie
- Ubuntu Noble (24.04 LTS)

## Packages

- **lldap** — Lightweight LDAP server with a web UI

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
Types: deb
URIs: https://francisrussell.github.io/ppa
Suites: $CODENAME
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/francis-russell-ppa.asc
EOF
sudo chmod 644 /etc/apt/sources.list.d/francis-russell-ppa.sources
```
