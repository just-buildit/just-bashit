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

## Removed names

`jb.toml` and `jb-deps.toml` are no longer read. A directory holding one of
them and no `bootstrap.toml` is refused, rather than treated as having no
manifest, so a project that declares its packages never silently installs
nothing:

```
error: jb.toml is no longer read, rename it: git mv jb.toml bootstrap.toml
```

`just-runit install` refuses the nearest `jb.toml` on its walk up the same
way. A `bootstrap.toml` beside a legacy file is read and the legacy file
ignored, and an explicit path argument is read whatever else is present.

Both names were read, with a warning, from 0.5.0 until every adopter had
renamed (#30): these scripts are fetched live from the CDN on every CI run,
so a hard cutover would have broken every repository in the window between
the publish and its rename.

To migrate:

```sh
git mv jb.toml bootstrap.toml
```

Nothing inside the file changes.
