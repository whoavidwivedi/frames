name: Feature Request
description: Suggest an idea or enhancement for Frames
labels: ["enhancement"]
body:
  - type: markdown
    attributes:
      value: |
        We appreciate your ideas to make Frames the best native video player for macOS.
  - type: textarea
    id: problem
    attributes:
      label: Problem or Motivation
      description: Is your feature request related to a problem or workflow limitation?
      placeholder: I'm always frustrated when...
    validations:
      required: true
  - type: textarea
    id: solution
    attributes:
      label: Proposed Solution / Feature
      description: Describe what you want to happen and how it should look or behave.
    validations:
      required: true
  - type: textarea
    id: alternatives
    attributes:
      label: Alternatives Considered
      description: Any alternative solutions or features you've considered.
