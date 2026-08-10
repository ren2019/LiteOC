# LiteOC

[中文](README.md) | [English](README.en.md)

A lightweight macOS menu-bar VPN client built around [openconnect](https://www.infradead.org/openconnect/) for **AnyLink** and compatible AnyConnect SSL VPN gateways.

[AnyLink](https://github.com/bjdgyc/anylink) is a widely used open-source SSL VPN server in China. LiteOC provides one-click connect/disconnect from the menu bar, stores the PIN in macOS Keychain, and keeps connection parameters in an editable configuration file.

## Features

- 🌐 **Menu-bar status**: gray when offline, color when connected, and alternating color/gray while connecting
- 🔐 **PIN stored only in macOS Keychain** — never written to disk, configuration, source code, or Git
- 🪟 **Graphical configuration** for gateway, user, and group; masked certificate fingerprint with reveal control; and a PIN row that opens Keychain or accepts a new PIN
- 🔒 **Certificate TOFU**: leave the fingerprint empty to discover `pin-sha256` on first connection and save it to the configuration
- 🎯 **Assigned VPN IP detection** from OpenConnect output rather than a hard-coded network range
- 🛡️ **Security boundary**: the OpenConnect path is fixed and configuration is parsed rather than executed. See [ADR-0001](docs/adr/0001-openconnect-path-not-user-configurable.md).

## Download and install

**Graphical installation (no Terminal required):** open the [latest release](https://github.com/ren2019/LiteOC/releases/latest), download `LiteOC-*.pkg`, and double-click it. Enter your macOS login password when prompted. The installer places `vpnctl` in `/usr/local/sbin`, the self-contained OpenConnect bundle in `/usr/local/libexec/liteoc`, a path-scoped passwordless sudo rule for `vpnctl`, and LiteOC.app in `/Applications`. **Homebrew is not required.**

> The package is ad-hoc signed and not notarized. If Gatekeeper blocks the first launch, open System Settings → Privacy & Security and choose **Open Anyway**.

**Build from source (Terminal and Homebrew required):**

```bash
cd gui && ./build.sh && sudo sh setup-root.sh
```

Apple Silicon and macOS 12 or later are required.

## Use

1. Open **LiteOC** from Launchpad; a globe icon appears in the menu bar.
2. Choose **Configure…**, enter the gateway, user, and group, leave the certificate empty if desired, and save the PIN.
3. Choose **Connect**. The connected state displays the assigned VPN IP.
4. Choose **Disconnect** to stop the connection.

For a CLI fallback, run `./connect.sh`; it reads the same configuration from `~/Library/Application Support/LiteOC/config`.

## Configuration

`~/Library/Application Support/LiteOC/config` is a commented `KEY=VALUE` file. The graphical configuration window edits this file, and it can also be edited directly. **It never contains the PIN.**

## Documentation

- [CONTEXT.md](CONTEXT.md) — domain glossary
- [docs/config-spec.md](docs/config-spec.md) — configuration decisions D1–D9 and implementation status
- [docs/prd-config-extraction.md](docs/prd-config-extraction.md) — product requirements
- [docs/adr/](docs/adr/) — ADR-0001 for the executable-path security boundary and ADR-0002 for certificate TOFU

## Relationship to openconnect-gui

[openconnect-gui](https://gitlab.com/openconnect/openconnect-gui) is a general-purpose, cross-platform, full-featured client for Windows, macOS, and Linux. It supports OTP, client certificates, PKCS#11 hardware tokens, and multiple profiles. LiteOC intentionally trades that breadth for a low-friction single scenario.

| | openconnect-gui | LiteOC |
|---|---|---|
| Positioning | General-purpose full GUI | Thin AnyLink / PIN-only wrapper |
| Platforms | Windows / macOS / Linux | macOS only |
| Credentials | Qt-managed storage | **PIN only in Keychain** |
| Certificate | Fingerprint supplied manually | **TOFU** discovery and persistence |
| Privilege | macOS administrator prompt on launch | **NOPASSWD scoped to one executable** |
| Size | Qt, 1,000+ commits | About 300 lines of Swift plus one shell helper |

Choose **LiteOC** for macOS, an AnyLink/PIN-only gateway, menu-bar connect/disconnect, and Keychain-backed PIN storage. Choose **openconnect-gui** when you need OTP, client certificates, hardware tokens, multiple profiles, or cross-platform support.

## Supported scope

**Supported:** AnyLink and OpenConnect-compatible SSL VPN gateways. Change the four gateway fields and PIN to point at another deployment; coworkers can share the configuration while keeping separate Keychain PINs.

**Not supported:** OpenVPN, WireGuard, IPsec, SangFor EasyConnect proprietary protocol, SSO/SAML, client certificates, or non-macOS systems.

## Troubleshooting

- “Incorrect username or password” → save the correct PIN again in **Configure…**.
- “Certificate discovery failed” → enter a `pin-sha256:…` value manually in the certificate field.
- Check actual status: `sudo /usr/local/sbin/vpnctl status ~/Library/Application\ Support/LiteOC/config`
- Read OpenConnect logs: `cat /tmp/liteoc-openconnect.log` or `log show --predicate 'process == "openconnect"' --last 5m`
