# Security policy

## Supported release

Security fixes are applied to the current maintained release line. For the initial public release, that line is `1.0.x`.

## Reporting a vulnerability

Do not publish secrets, private media, access tokens or exploitable proof-of-concept details in a public issue. Use GitHub's private vulnerability reporting feature if enabled for the repository. Otherwise, contact the project maintainer through a private channel listed in the repository profile.

Include the affected version, operating system, Flutter version, minimum reproduction steps and impact. Redact file paths, usernames, media contents and tokens from logs.

## Security design notes

- Android does not request `MANAGE_EXTERNAL_STORAGE`.
- Mobile media-library access is permission-gated and performed through platform media APIs.
- Desktop recursive scan starts only after explicit user selection of a folder; symbolic links are not followed.
- Browser file access uses browser-provided pickers/handles and downloads; the app cannot bypass browser permissions.
- Build/signing credentials are not included. Keep signing keys, certificates, provisioning files and passwords in local secure storage or GitHub Actions Secrets/Environments.
- Keep Flutter, platform SDKs and dependencies current and review dependency notices before releases.
