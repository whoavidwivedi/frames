name: Bug Report
description: Create a report to help us fix a bug in Frames
labels: ["bug"]
body:
  - type: markdown
    attributes:
      value: |
        Thanks for taking the time to report an issue! Please provide as much detail as possible.
  - type: input
    id: mac-model
    attributes:
      label: Mac Hardware & Apple Silicon Model
      description: e.g. MacBook Pro 16" (M3 Max, 36GB), Mac Studio (M2 Ultra)
      placeholder: Apple Silicon M-series
    validations:
      required: true
  - type: input
    id: os-version
    attributes:
      label: macOS Version
      description: e.g. macOS 14.5 Sonoma, macOS 15.1 Sequoia
      placeholder: macOS 14+
    validations:
      required: true
  - type: input
    id: app-version
    attributes:
      label: Frames Version
      description: e.g. v1.1.0 (check via ⌘K -> Check for Updates or App Menu)
      placeholder: v1.1.0
    validations:
      required: true
  - type: textarea
    id: description
    attributes:
      label: Describe the Bug
      description: A clear and concise description of what the bug is.
    validations:
      required: true
  - type: textarea
    id: steps
    attributes:
      label: Steps to Reproduce
      description: Detailed steps to reproduce the behavior.
      placeholder: |
        1. Open video '...'
        2. Press '...'
        3. Observe '...'
    validations:
      required: true
  - type: textarea
    id: expected
    attributes:
      label: Expected Behavior
      description: What did you expect to happen instead?
    validations:
      required: true
