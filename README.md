# plug.kak

[![GitHub release](https://img.shields.io/github/release/andreyorst/plug.kak.svg)](https://github.com/andreyorst/plug.kak/releases)
[![GitHub Release Date](https://img.shields.io/github/release-date/andreyorst/plug.kak.svg)](https://github.com/andreyorst/plug.kak/releases)
![Github commits (since latest release)](https://img.shields.io/github/commits-since/andreyorst/plug.kak/latest.svg)
![license](https://img.shields.io/github/license/andreyorst/plug.kak.svg)

**plug.kak** is a plugin manager for Kakoune editor, that aims to work somewhat
similar to [vim-plug](https://github.com/junegunn/vim-plug). It is being tested
against Kakoune 2018.09.04. If you're using development release, switch to [Kakoune_dev](https://github.com/andreyorst/plug.kak/tree/Kakoune_dev) branch.

## Installation

```sh
mkdir -p ~/.config/kak/plugins/
git clone https://github.com/andreyorst/plug.kak.git ~/.config/kak/plugins/plug.kak
```

And source `plug.kak` from your `kakrc`, or any of your configuration file.

```kak
source /path/to/your/kakoune_config/plugins/plug.kak/rc/plug.kak
```

If you cloned repo to your plugin installation dir, which defaults to `~/.config/kak/plugins/`
**plug.kak** will be able to manage itself along with another plugins.

## Usage

You can specify what plugins to install and load by using `plug` command:

```kak
# make sure that plug.kak is installed at plug_install_dir path
plug "andreyorst/plug.kak"

# branch or tag can be specified with second parameter:
plug "andreyorst/fzf.kak" "branch: master"
# you can add configurations to the plugin and enable them only if pluin was loaded:
evaluate-commands %sh{
    [ -z "${kak_opt_plug_loaded_plugins##*fzf.kak*}" ] || exit
    echo "map -docstring 'fzf mode' global normal '<c-p>' ': fzf-mode<ret>'"
    echo "set-option global fzf_file_command \"find . \( -path '*/.svn*' -o -path '*/.git*' \) -prune -o -type f -print\""
}

plug "https://github.com/alexherbo2/auto-pairs.kak"
evaluate-commands %sh{
    [ -z "${kak_opt_plug_loaded_plugins##*auto-pairs.kak*}" ] || exit
    echo "hook global WinCreate .* %{ auto-pairs-enable }"
    echo "map global normal <a-s> ': auto-pairs-surround<ret>'"
}
```

## Configuration

### Plugin installation directory

You can specify where to install plugins, in case you don't like default `~/.config/kak/plugins/` path, you can
use option `plug_install_dir`:

```kak
set-option global plug_install_dir '$HOME/.cache/kakoune_plugins'
```

Or any other path.

### Maximum downloads

To specify maximum amount of simultaneous downloads set `plug_max_simultanious_downloads`. Default value is `10`.

### Default git domain

Although you can use URLs inside `plugin` field, if you're using plugins from, say, Gitlab only, you can drop URLs, and set
default git domain to `https://gitlab.com`. Or to bitbucket, and any other git domain, as long as it similar to github's
in term of URL structure.

Default value is `https://github.com`

## Commands

**plug.kak** adds three commands:

- `plug-install` - Install all plugins specified in any configuration file;
- `plug-update` - Update installed plugins;
- `plug-clean` - Remove plugins, that are installed, but disabled in
  configuration files;
- `plug` - Load plugin from plugin installation directory.

Here are some examples:

### Installing new plugin

1. Add `plug "github_username/reponame"` to your `kakrc`;
2. Source your `kakrc` with `source` command, or restart Kakoune to tell **plug.kak** that configuration is changed;
3. Execute `plug-install` command;
4. Source your `kakrc` with `source` command, or restart Kakoune to load plugins.

### Updating installed plugins

1. Execute `plug-update` command;
2. Restart Kakoune to load updated plugins.

### Removing unneded plugins

1. Delete desired `plug` entry from your `kakrc` or comment it;
2. Source your `kakrc` with `source` command, or restart Kakoune to tell **plug.kak** that configuration is changed;
3. Execute `plug-clean` command;
4. (Optional) If you didn't restarted Kakoune at 2. restart it to unload uninstalled plugins.

