# Contributing

Thank you for improving PlansBar.

1. Create a focused branch.
2. Keep the macOS app independent from Node.js and npm at runtime.
3. Use synthetic repository names such as `sample-api` and `mobile-app` in tests and documentation.
4. Run the relevant checks:

```bash
swift build -c release
cd Dashboard && npm test && npm run build
```

Before opening a pull request, run `Scripts/verify-public-tree.sh` against a built app bundle. Never attach real plan contents, absolute paths, private repository names, screenshots with local data, or secrets.
