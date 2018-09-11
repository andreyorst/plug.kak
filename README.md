# plug.kak

**plug.kak** is a plugin manager for Kakoune editor, that aims to work somewhat
similar to [vim-plug](https://github.com/junegunn/vim-plug). It is being tested
against Kakoune 2018.09.04. If you're using Kakoune builds from git master, switch to
kak-git branch.

## Installation

``` sh
mkdir -p ~/.config/kak/plugins/
git clone https://github.com/andreyorst/plug.kak.git ~/.config/kak/plugins/plug.kak
```

And source `plug.kak` from your `kakrc`, or any of your configuration file.

If you cloned repo to your plugin installation dir, which defaults to `~/.config/kak/plugins/`
**plug.kak** will be able to manage itself along with another plugins.

## Usage

You can specify what plugins to install and load by using `plug` command:

```sh
plug andreyorst/plug.kak # only if plug.kak repo exists at plugin installation path. 
...
plug github_username/repo_name
```

To specify where to install plugins, in case you don't like default `~/.config/kak/plugins/` path, you can
use option `plug_install_dir`:

```kak
set-option global plug_install_dir '$HOME/.cache/kakoune_plugins'
```

Or any other path.

## Commands

**plug.kak** adds three commands:

- `plug-install` - Install all plugins specified in any configuration file
- `plug-update` - Update installed plugins
- `plug-clean` - Remove plugins, that are installed, but disabled in
  configuration files.

[Kakoune]: http://kakoune.org
[IRC]: https://webchat.freenode.net?channels=kakoune
[IRC Badge]: https://img.shields.io/badge/IRC-%23kakoune-blue.svg

