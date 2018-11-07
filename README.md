# plug.kak
[![GitHub issues](https://img.shields.io/github/issues/andreyorst/plug.kak.svg)](https://github.com/andreyorst/plug.kak/issues) 
![license](https://img.shields.io/github/license/andreyorst/plug.kak.svg)

**plug.kak** is a plugin manager for Kakoune editor, that aims to work somewhat
similar to [vim-plug](https://github.com/junegunn/vim-plug). This is development branch that keeps track of Kakoune's master branch changes.
All features that are being development here will be eventually backported to **plug.kak** branches of two latest Kakoune stable releases.

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

`plug` command supports these options:
- git checkout before load: `"branch: branch_name"`, `tag: tag_name`, `commit: commit_hash`.
- `noload` - skip loading of installed plugin, but load it's configurations. Useful with kak-lsp, and plug.kak itself
- `do %{...}` - post-update hook, executes shell code only after updates of plugin. Useful for plugins that need building.
- `%{configurations}` - last parameter is always configurations of the plugin. Configurations are applied only if plugin is installed.

You can specify what plugins to install and load by using `plug` command:

```sh
# make sure that plug.kak is installed at plug_install_dir path
plug "andreyorst/plug.kak" noload

# branch or tag can be specified with second parameter:
plug "andreyorst/fzf.kak" "branch: master" %{
    # you can add configurations to the plugin and enable them only if plugin was loaded:
    map -docstring 'fzf mode' global normal '<c-p>' ': fzf-mode<ret>'
    set-option global fzf_preview_width '65%'
    evaluate-commands %sh{
        if [ ! -z "$(command -v fd)" ]; then
            echo "set-option global fzf_file_command 'fd . --no-ignore --type f --follow --hidden'"
        else
            echo "set-option global fzf_file_command find"
        fi
        if [ ! -z "$(command -v bat)" ]; then
            echo "set-option global fzf_highlighter 'bat'"
        elif [ ! -z "$(command -v highlight)" ]; then
            echo "set-option global fzf_highlighter 'highlight'"
        fi
    }
}

plug "https://github.com/alexherbo2/auto-pairs.kak" %{
    hook global WinCreate .* %{ auto-pairs-enable }
    map global normal <a-s> ': auto-pairs-surround<ret>'
}

# example of kak-lsp configuration with plug.kak
# 'do %{cargo build --release}' will be executed after every successful update
plug "ul/kak-lsp" noload do %{cargo build --release} %{
    hook global WinSetOption filetype=(c|cpp|rust) %{
        evaluate-commands %sh{ kak-lsp --kakoune -s $kak_session }
        lsp-auto-hover-enable
        set-option global lsp_hover_anchor true
    }
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

**plug.kak** adds four commands:

- `plug-install` - Install all plugins specified in any configuration file;
- `plug-update` - Update installed plugins;
- `plug-clean` - Remove plugins, that are installed, but disabled in
  configuration files;
- `plug` - Load plugin from plugin installation directory.

Here are some examples:

### Installing new plugin

1. Add `plug "github_username/reponame"` to your `kakrc`;
2. Source your `kakrc` with `source` command, or restart Kakoune to tell **plug.kak** that configuration is changed;
3. Execute `plug-install` command. Plugins will be loaded and configured accordingly to your kakrc;

### Updating installed plugins

1. Execute `plug-update` command;
2. Restart Kakoune to load updated plugins.

### Removing unneded plugins

1. Delete desired `plug` entry from your `kakrc` or comment it;
2. Source your `kakrc` with `source` command, or restart Kakoune to tell **plug.kak** that configuration is changed;
3. Execute `plug-clean` command;
4. (Optional) If you didn't restarted Kakoune at 2. restart it to unload uninstalled plugins.

