# Security Policy

## Supported Versions

This project is under active development and does not currently publish stable
release branches. Security fixes should target `main` unless a maintained
release branch is announced.

## Reporting a Vulnerability

Please do not open a public issue for a vulnerability that exposes credentials,
tokens, server URLs, private media metadata, or a reproducible account/session
compromise.

Report privately through GitHub's private vulnerability reporting feature if it
is enabled for this repository. If it is not enabled, contact the repository
owner through a private channel and include only the minimum information needed
to reproduce the issue.

Useful reports include:

- A concise description of the problem.
- Affected commit or version.
- Reproduction steps.
- Expected and actual behavior.
- Whether credentials, tokens, or private media metadata are exposed.
- Any relevant logs with secrets redacted.

## Secret Handling

Never include the following in issues, pull requests, screenshots, or logs:

- Emby usernames, passwords, access tokens, API keys, or session IDs.
- Private server hostnames or LAN/WAN URLs.
- Apple signing identities, provisioning profiles, team IDs, or device IDs.
- Local filesystem paths that reveal private media library structure.

## Dependency Security

The app uses native multimedia dependencies outside this repository. Keep your
local libmpv, FFmpeg, MoltenVK, and related builds up to date and review their
license and security advisories before redistribution.
