# plug.kak
[![GitHub issues](https://img.shields.io/github/issues/andreyorst/plug.kak.svg)](https://github.com/andreyorst/plug.kak/issues)
![license](https://img.shields.io/github/license/andreyorst/plug.kak.svg)


![image](https://user-images.githubusercontent.com/19470159/51197223-f2c26a80-1901-11e9-9494-b79ce823a364.png)

**plug.kak** is a plugin manager for Kakoune editor, that aims to work somewhat similar to
[vim-plug](https://github.com/junegunn/vim-plug). This plugin currently supports two latest
releases of Kakoune and Kakoune git branch. Default branch is latest release, named accordingly.
This branch is tested agains Kakoune v2019.01.20. If you're using Kakoune builds from Github repo, please use
[kakoune-git](https://github.com/andreyorst/plug.kak/tree/kakoune-git) branch.

## Installation

You need to create a `plugins` directory at your Kakoune configuration path. You
can check correct location by evaluating this command in Kakoune:
`echo %val{config}`.

```sh
mkdir -p ~/.config/kak/plugins/
```

In my case it is `$HOME/.config/kak`. After directory was created, you need to
clone this repo there with this command:

```sh
git clone https://github.com/andreyorst/plug.kak.git ~/.config/kak/plugins/plug.kak
```

And source `plug.kak` from your `kakrc`, or any of your configuration file.

```kak
source "%val{config}/plugins/plug.kak/rc/plug.kak"
```

**plug.kak** can work from any directory, but if you installed it to your plugin
installation dir, which defaults to `%val{config}/plugins/`
**plug.kak** will be able to update itself along with another plugins.

## Usage
You can specify what plugins to install and load by using `plug` command. This
command accepts one or more arguments, which are keywords and attributes, that
change how **plug.kak** behaves. For most plugins it is usually enough to
provide single argument, which is plugin's author name, and plugin name
separated with slash. **plug.kak** will look for this plugin on GitHub, and
download it for you.
If you want to install plugin from place other than GitHub, like GitLab or
Gitea, `plug` accepts URL as first parameter.
So in most cases it is enough to add this into your `kakrc` to use a plugin:

```kak
plug "delapouite/kakoune-text-objects"
```

After that you'll need to re-source your `kakrc` or restart Kakoune to let
**plug.kak** know that configuration was updated, and use a `plug-install`
command to install new plugins. More information about commands available
in [Commands](#Commands) section.

### Keywords and attributes
As was already mentioned `plug` command accepts optional attributes, that change
how **plug.kak** works, or add additional steps for `plug` to perform for you.
These are keywords to use:
- [branch, tag, commit](#Branch-Tag-or-Commit)
- [load](#Loading-subset-of-files-from-plugin-repository)
- [noload](#Skipping-loading-of-a-plugin)
- [do](#Automatically-do-certain-tasks-on-install-or-update)
- [config](#Handling-user-configurations)

#### Branch, Tag or Commit
`plug` can checkout a plugin to desired branch, commit or tag before load. To do
so, add this after plugin name: `branch "branch_name"`, `tag "tag_name"` or
`commit "commit_hash"`.

#### Loading subset of files from plugin repository
If you want to load only part of a plugin (assuming that plugin allows this) you
can use `load` keyword followed by filenames. If `load` isn't specified `plug`
uses it's default value, which is `*.kak`, and by specifying a value, you just
override default one. Here's an example:

```kak
plug "lenormf/kakoune-extra" load %{
    hatch_terminal.kak
    lineindent.kak
}
```

#### Skipping loading of a plugin
Some plugins require to be loaded by calling an external tool. In such case use
`noload` attribute to skip loading of installed plugin. Useful with plug.kak
itself, because it is already loaded by user configuration.

```kak
plug "andreyorst/plug.kak" noload
```

#### Automatically do certain tasks on install or update
The `do` keyword is a post-update hook, that executes shell code only after
successful update of plugin or a fresh installation of one. Useful for plugins
that need to compile some parts of it.

```kak
plug "ul/kak-lsp" noload do %{cargo build --release}
```

#### Handling user configurations
**plug.kak** also capable to handle plugin configurations. You can specify them
by using `config` keyword and list of configurations, or via last parameter,
since it is always treated as configurations of the plugin. Configurations are
applied only if plugin is installed.

```kak
plug "andreyorst/fzf.kak" config %{
    map -docstring 'fzf mode' global normal '<c-p>' ': fzf-mode<ret>'
    set-option global fzf_preview_width '65%'
    evaluate-commands %sh{
        if [ ! -z "$(command -v fd)" ]; then
            echo "set-option global fzf_file_command 'fd . --no-ignore --type f --follow --hidden'"
        fi
    }
}
```

## Configuration

### Plugin installation directory

You can specify where to install plugins, in case you don't like default
`~/.config/kak/plugins/` path, you can use option `plug_install_dir`:(note: if you want to use shell variables in the path, consider using shell expansion like in this example)

```kak
set-option global plug_install_dir %sh{ echo $HOME/.cache/kakoune_plugins }
```


Or any other path.

### Maximum downloads

To specify maximum amount of simultaneous downloads set
`plug_max_simultaneous_downloads`. Default value is `10`.

### Default git domain

Although you can use URLs inside `plugin` field, if you're using plugins from,
say, Gitlab only, you can drop URLs, and set default git domain to
`https://gitlab.com`. Or to Bitbucket, and any other git domain, as long as it
similar to github's in term of URL structure.

Default value is `https://github.com`

## Commands

**plug.kak** adds four commands:

- `plug-install` - Install all plugins specified in any configuration file;
- `plug-update` - Update installed plugins;
- `plug-clean` - Remove plugins, that are installed, but disabled in
  configuration files;
- `plug-list` - List all installed plugins, and check for updates;
- `plug` - Load plugin from plugin installation directory by its name.

Here are some examples:

### Installing new plugin

1. Add `plug "github_username/reponame"` to your `kakrc`;
2. Source your `kakrc` with `source` command, or restart Kakoune to tell **plug.kak** that configuration is changed;
3. Execute `plug-install` command, the `*plug*` buffer will show up to illustrate progress. Plugins will be loaded and configured accordingly to your kakrc;

### Updating installed plugins

1. Execute `plug-update` command, the `*plug*` buffer will show up to illustrate progress;
2. Restart Kakoune to load updated plugins.

### Removing unneeded plugins

1. Delete desired `plug` entry from your `kakrc` or prefix it with `nop`, or just comment it;
2. Source your `kakrc` with `source` command, or restart Kakoune to tell **plug.kak** that configuration is changed;
3. Execute `plug-clean` command, the `*plug*` buffer will show up to illustrate progress;
4. (Optional) If you didn't restarted Kakoune at 2. restart it to unload uninstalled plugins.

