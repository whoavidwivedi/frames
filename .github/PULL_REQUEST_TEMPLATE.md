## 📋 Pull Request Overview

### Summary
<!-- Provide a clear, concise summary of the changes and motivation behind this PR -->

### Type of Change
- [ ] 🚀 New feature (non-breaking change which adds functionality)
- [ ] 🐛 Bug fix (non-breaking change which fixes an issue)
- [ ] 🎨 UI/UX refinement (visual styling, typography, animations)
- [ ] ⚡ Performance optimization (GPU memory, Metal pipelines, decoding)
- [ ] 🛠️ Refactoring / Architecture enhancement
- [ ] 📝 Documentation update
- [ ] 🧪 Tests addition or update
- [ ] 📦 CI/CD / Release automation

---

## 🔬 Engineering & Architecture Details
<!-- Explain what architectural components or modules are affected (e.g., VideoToolboxDecoder, Metal 3 renderer, WindowManager, ShadcnCommand, UpdateManager) -->

---

## 🧪 Testing & Verification

### Automated Test Suite Execution
- [ ] Ran local test suite: `frames --run-tests`
- [ ] Total passed: `_____ PASSED, 0 FAILED`
- [ ] All 34 test categories green (458+ automated tests)

### Manual Verification Checklist
- [ ] Window dragging / double-click interactions tested
- [ ] Keyboard shortcuts tested without intercepting text input or dialogs
- [ ] Memory footprint verified on Apple Silicon Unified Memory (< 200MB)
- [ ] Dark / Light mode adaptive contrast verified
- [ ] Command Palette (`⌘K`) search and actions verified

---

## 🔒 Apple Silicon & Security Compliance
- [ ] Hardened Runtime compatible
- [ ] No private AppKit / SkyLight API usage
- [ ] Sandboxing / Gatekeeper compliance checked
