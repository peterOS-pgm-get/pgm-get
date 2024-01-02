# Program-Get

The program installation tool for [PeterOS](https://github.com/Platratio34/peterOS)

## Command:

```console
pgm-get [mode] ...
```

### Modes

#### Install
```console
pgm-get install [program] [version]
```

**Must be run as super user**

Installs `program` with optional version.
If version is not specified it will get the current latest stable version of the program.

#### Uninstall
```console
pgm-get uninstall [program]
```

**Must be run as super user**

Uninstalls `program`.

#### Update
```console
pgm-get update
```

Update the cached manifest of all programs.
Manifest is automatically updated on computer start.

#### Upgrade
```console
pgm-get upgrade
```

**Must be run as super user**

Upgrade all programs installed at a version lower that the current latest stable version.

#### List
```console
pgm-get list [installed]
```

Lists all programs in manifest, and current installed versions if they are installed.
If run with `installed`, it will only list installed programs.

## Program Package
```lua
_G.pgmGet
```

### Variables

| Name | Default | Description |
| ---- | ------- | ----------- |
| `warnOld` | `true` | If the a warning should be issued on computer startup if any program is running an un-forced old version |

### Functions

| Signature | Return | Description |
| --------- | ------ | ----------- |
| `updateManifest(warnOld: bool)` | `nil` | Updates local cached program manifest |