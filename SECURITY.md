# Security Policy

## Supported Versions

We release patches and security improvements for the latest minor version of Frames:

| Version | Supported          |
| :------ | :----------------- |
| 1.3.x   | :white_check_mark: |
| 1.2.x   | :x:                |
| 1.1.x   | :x:                |
| < 1.1.0 | :x:                |

---

## Architecture & Security Posture

Frames is engineered with strict Apple Silicon memory and execution boundaries:
- **Zero Legacy Dynamic Code Injection**: Pure Swift 6 compiled with strict memory safety checks and Hardened Runtime compatibility.
- **Metal 3 Direct IOSurface Pipeline**: Decoded video frames reside in hardware-allocated `IOSurface` unified memory buffers without intermediate unsanitized user-space heap manipulations.
- **OTA Verification**: In-app OTA updates verify package checksums (SHA-256) and bundle structural signatures before staging atomic swaps.

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
