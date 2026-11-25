# Security Policy

## Supported Versions

We release patches and security improvements for the latest minor version of Frames:

| Version | Supported          |
| :------ | :----------------- |
| 2.0.x   | :white_check_mark: |
| < 2.0.0 | :x:                |

---

## Architecture & Security Posture

Frames is engineered with strict Apple Silicon memory and execution boundaries:
- **Zero Legacy Dynamic Code Injection**: Swift compiled with strict memory safety checks and the Hardened Runtime enabled for distributed builds.
- **Metal 3 Direct IOSurface Pipeline**: Decoded video frames reside in hardware-allocated `IOSurface` unified memory buffers without intermediate unsanitized user-space heap manipulations.
- In-app updates verify release checksums and bundle identity. Releases without an Apple Developer ID use ad-hoc signing and require explicit consent. Checksums verify integrity. Developer ID signatures additionally authenticate the publisher.

---

## Reporting a Vulnerability

If you discover a security vulnerability or security defect in Frames, please **do not open a public issue**. Instead, follow responsible disclosure:

1. Use GitHub's [Private Vulnerability Reporting](https://github.com/whoavidwivedi/frames/security/advisories/new).
2. Or email the maintainer directly at `theavidwivedi@gmail.com` with the subject line `[SECURITY] Frames Vulnerability Report`.

### What to Include
- Detailed description of the vulnerability and impact.
- Exact macOS version and Apple Silicon hardware model.
- Minimal reproducible sample (sample media file, script, or crash trace).
- Potential mitigation or patch if identified.

We will acknowledge receipt within 48 hours and work with you to test and release an advisory and patch.
