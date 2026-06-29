# Contributing to DashPad

## Opening an Issue

**Bug reports** should include: iOS/iPadOS version, device model, steps to reproduce, expected behaviour, and actual behaviour. A crash log or screenshot helps. One bug per issue.

**Feature requests** should describe the problem you are trying to solve, not just the solution you have in mind. Check existing issues first to avoid duplicates.

## Opening a Pull Request

1. Fork the repository and create a branch from `main`.
2. Keep each PR focused on a single concern, one bug fix or one feature. Reviewers can give better feedback on small, focused changes.
3. Make sure the project builds cleanly (`Product > Build` in Xcode) before opening the PR.
4. Describe what changed and why in the PR body, and note how you tested it on-device.

## Code Style

- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- Match the style of the surrounding code: naming, comment density, and structure.
- Add a `// MARK: -` section divider in any file that exceeds ~100 lines.
- **No new dependencies.** The project deliberately uses only Apple system frameworks. If you believe a dependency is warranted, open an issue to discuss it before implementing.

## License for Contributions

By submitting a contribution you agree that it is licensed under the same [PolyForm Noncommercial License 1.0.0](LICENSE) terms as this project, and that the maintainer (Rafael Pagés) may also offer it under separate commercial license terms.

## Commercial Use Questions

For questions about commercial licensing, contact dashpad@rafapages.com.
