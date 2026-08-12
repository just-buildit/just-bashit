# bootstrap.toml

`bootstrap.toml` declares what a repository needs **before** its own language
ecosystem can run: system packages, and the external tools fetched from the
just-buildit namespace.

It sits at the repository root and is read by
[`install-deps`](install-deps.md), [`setup-system`](setup-system.md),
[`inspect`](inspect.md), and `just-runit install`.

```toml
[project]
name    = "my-project"
version = "0.1.0"

[tools.install-deps]
source = "just-bashit:install-deps"
groups = ["runtime", "dev"]

[runtime.apt]
packages = ["build-essential", "cmake"]

[dev.apt]
packages = ["clang-format", "shellcheck"]
```

______________________________________________________________________

## Why it is not called `jb.toml`

It was, until 0.5.0. That name pointed at the wrong tool.

`jb` reads as **just-buildit** — the PEP 517 build backend — and that tool has
never opened this file. It reads `pyproject.toml`, like every other PEP 517
backend. The file was named after a token that meant three different things at
once: the GitHub org, the build backend, and (via a symlink the installer
created) the script runner that actually reads it.

Naming it for a *tool* was the deeper mistake, and it would have been a
mistake even without the collision:

- **Two different tools already read it.** `just-runit install` reads
    `[tools.*]`; the package groups are read by `install-deps`, which is a
    separate script fetched over HTTPS. A file named for one consumer is
    already wrong when there are two.
- **The tool names were unsettled.** Pinning the file to `jbx` would have bet
    on a name that was itself under review.

`bootstrap.toml` names what the file *declares*, which does not move when the
tools are renamed. The precedent is asdf's `.tool-versions`, which survived
the move to mise intact precisely because it was content-named;
`Cargo.toml` and `package.json` got away with tool-naming because those tools
are singular and stable.

______________________________________________________________________

## Deprecated names

`jb.toml` and `jb-deps.toml` are still read, and print a warning:

```
warning: jb.toml is deprecated, rename it to bootstrap.toml
```

Resolution order is `bootstrap.toml`, then `jb-deps.toml`, then `jb.toml`.
An explicit path argument beats all three.

Both legacy names are read during the transition because these scripts are
fetched live from the CDN on every CI run — a hard cutover would break every
repository that had not yet renamed, in the window between the publish and
their rename. They will be removed in a later release.

To migrate:

```sh
git mv jb.toml bootstrap.toml
```

Nothing inside the file changes.
