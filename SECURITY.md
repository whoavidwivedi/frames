# Security Policy

## Supported Versions

We release patches and security improvements for the latest minor version of Frames:

| Version | Supported          |
| :------ | :----------------- |
| 1.9.x   | :white_check_mark: |
| < 1.9.0 | :x:                |

---

## Architecture & Security Posture

Frames is engineered with strict Apple Silicon memory and execution boundaries:
- **Zero Legacy Dynamic Code Injection**: Swift compiled with strict memory safety checks and the Hardened Runtime enabled for distributed builds.
- **Metal 3 Direct IOSurface Pipeline**: Decoded video frames reside in hardware-allocated `IOSurface` unified memory buffers without intermediate unsanitized user-space heap manipulations.
- **OTA Verification**: In-app updates and the command-line installer verify the published SHA-256 checksum and require a valid Developer ID Application signature (all architectures and nested code) before installation. Unsigned, ad-hoc signed, or checksum-mismatched packages are rejected.

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
