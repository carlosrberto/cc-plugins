# claude-code-plugins

This is my [marketplace](https://code.claude.com/docs/en/plugin-marketplaces) of Claude Code plugins. Feel free to use and contribute.

## Plugins

| Plugin | Description |
| ------ | ----------- |
| `safeguards` | Hooks-only defensive guards (credential-read, AI-attribution, force-push) — [README](./plugins/safeguards/README.md) |

## Install

```
/plugin marketplace add carlosrberto/claude-code-plugins
/plugin install safeguards@claude-code-plugins
/reload-plugins
```

## Auto-register the marketplace

To have a repo pick up this marketplace automatically, add this to that repo's
checked-in `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "claude-code-plugins": {
      "source": { "source": "github", "repo": "carlosrberto/claude-code-plugins" }
    }
  },
  "enabledPlugins": {
    "safeguards@claude-code-plugins": true
  }
}
```

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for repo layout, local development,
verification, and the release process.

## License

MIT — see [LICENSE](./LICENSE).
