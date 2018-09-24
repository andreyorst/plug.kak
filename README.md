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

```kak
source /path/to/your/kakoune_config/plugins/plug.kak/rc/plug.kak
```

If you cloned repo to your plugin installation dir, which defaults to `~/.config/kak/plugins/`
**plug.kak** will be able to manage itself along with another plugins.

## Usage

You can specify what plugins to install and load by using `plug` command:

```bash
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

plug "alexherbo2/auto-pairs.kak"
evaluate-commands %sh{
    [ -z "${kak_opt_plug_loaded_plugins##*auto-pairs.kak*}" ] || exit
    echo "hook global WinCreate .* %{ auto-pairs-enable }"
    echo "map global normal <a-s> ': auto-pairs-surround<ret>'"
}
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

Here are some examples:

### Installing new plugin

1. Add `plug github_username/reponame` to your `kakrc`;
2. Source your `kakrc` with `source` command, or restart Kakoune to tell plug.kak that configuration is changed;
3. Execute `plug-install` command;
4. Source your `kakrc` with `source` command, or restart Kakoune to load plugins.

### Updating installed plugins

1. Execute `plug-update` command;
2. Restart Kakoune to load updated plugins.

### Removing unneded plugins

1. Delete desired `plug` entry from your `kakrc` or comment it;
2. Source your `kakrc` with `source` command, or restart Kakoune to tell plug.kak that configuration is changed;
3. Execute `plug-clean` command;
4. (Optional) If you didn't restarted Kakoune at 2. restart it to unload uninstalled plugins.
