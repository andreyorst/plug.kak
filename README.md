# plug.kak
[![GitHub issues][1]][2] ![license][3]

![plug.kak][4]

**plug.kak** is a plugin manager for Kakoune, that was inspired by [vim-plug][5] and [use-package][6].
It can install and update plugins, run post-update actions, and helps to encapsulate the configuration within itself.


## Installation

**plug.kak** can be installed anywhere in your system, but in order to update itself, it is required to install **plug.kak** in the plugin installation directory.
By default, **plug.kak** installs plugins to the `%val{config}/plugins`, which is usually at `$HOME/.config/kak/plugins`:

``` sh
mkdir -p $HOME/.config/kak/plugins
git clone https://github.com/andreyorst/plug.kak.git $HOME/.config/kak/plugins/plug.kak
```

Now, when **plug.kak** is installed, we need to tell Kakoune about it.
Add this to the `kakrc` file:

``` kak
source "%val{config}/plugins/plug.kak/rc/plug.kak"
plug "andreyorst/plug.kak" noload
```

Alternatively, this process can be automated, by adding the following snippet to the `kakrc`:

``` sh
evaluate-commands %sh{
    plugins="$kak_config/plugins"
    mkdir -p "$plugins"
    [ ! -e "$plugins/plug.kak" ] && \
        git clone -q https://github.com/andreyorst/plug.kak.git "$plugins/plug.kak"
    printf "%s\n" "source '$plugins/plug.kak/rc/plug.kak'"
}
plug "andreyorst/plug.kak" noload
```

This will create all needed directories on Kakoune launch, and download **plug.kak** if it is not installed already.

**Note**: `plug "andreyorst/plug.kak" noload` is needed to register **plug.kak** as manually loaded plugin, so `plug-clean` will not delete **plug.kak**.


## Usage

All plugins are installed and loaded with the `plug` command.
This command accepts one-or-more arguments, which are keywords and attributes, that change how **plug.kak** behaves.

The first strict rule of the `plug` command is that the first argument is always the plugin name formatted as in GitHub URL: `"author/repository"`.

``` kak
plug "author/repository"
```

By default **plug.kak** will look for the plugin at GitHub.com, and download it.
When the plugin is hosted on a different service, a URL can be used as the first argument.
So in most cases it is enough to add this to the `kakrc` to use a plugin:

```kak
plug "delapouite/kakoune-text-objects"
```

Or with URL:

```kak
plug "https://gitlab.com/Screwtapello/kakoune-inc-dec"
```

After adding this, `kakrc` needs to be re-sourced to let **plug.kak** know that configuration was changed.
Alternatively, Kakoune can be restarted.
After that newly added plugins can be installed with the `plug-install` command.
More information about other commands available in [Commands](#Commands) section.


### Keywords and attributes

The `plug` command accepts optional attributes, that change how **plug.kak** works, or add additional steps for `plug` to perform.

These keywords are supported:

- [branch, tag, commit](#branch-tag-or-commit)
- [load-path](#loading-plugin-from-different-path)
- [noload](#skipping-loading-of-a-plugin)
- [do](#automatically-do-certain-tasks-on-install-or-update)
- [theme](#installing-color-schemes)
- [config](#handling-user-configurations)
- [defer](#deferring-plugin-configuration)
- [demand](#demanding-plugin-module-configuration)
- [ensure](#ensuring-that-plugins-are-installed)


#### Branch, Tag or Commit

`plug` can checkout a plugin to desired branch, commit or tag before loading it.
It can be done by adding the following keywords with parameters: `branch "branch_name"`, `tag "tag_name"` or `commit "commit_hash"`.


#### Loading plugin from different path

Plugins can be loaded from arbitrary path by specifying the `load-path` keyword and providing the path as an argument:

``` kak
plug "plugin_name" load-path "~/Development/plugin_dir"
```

However all `plug` related commands, like `plug-update` or `plug-clean` will not work for plugins that aren't installed to `plug_install_dir`.


#### Skipping loading of a plugin

If plugin needs to be loaded manually, the `noload` keyword can be used.
This can also be used to avoid loading the plugin second time, like in the example with **plug.kak** from the [installation](#installation) section:

```kak
source "%val{config}/plugins/plug.kak/rc/plug.kak"
plug "andreyorst/plug.kak" noload
```

Note, that plugins with the `noload` keyword are still configured and managed.
See [handling-user-configuration](#handling-user-configurations) for more details.


#### Automatically do certain tasks on install or update

When the plugin requires some additional steps to preform after installation or update, the `do` keyword can be used.
This keyword expects the body which will be executed in the shell, thus it can only contain shell commands, not Kakoune commands.

```kak
plug "ul/kak-lsp" do %{
    cargo build --release --locked
    cargo install --force --path .
}
```

In the example above **plug.kak** will run these `cargo` commands after `kak-lsp` was installed or updated.

**Note** that even though this is technically a shell expansion, the `%sh{}` expansion can't be used with `do`, as it will be evaluated immediately each time `kakrc` loaded.
Use `%{}` instead.


#### Installing color schemes

To register the plugin as a color scheme, use `theme` keyword.
Such plugins will be copied to the `%val{config}/colors` directory.

```kak
plug "andreyorst/base16-gruvbox.kak" theme config %{
    colorscheme base16-gruvbox-dark-soft
}
```


#### Ensuring that plugins are installed

`plug` command can be explicitly told to install the plugin automatically with the `ensure` keyword.
The `plug_always_ensure` option can be set to `true` to perform this for each and every plugin specified in the `kakrc`.


#### Handling user configurations

The configuration of the plugin is preformed only when the plugin is installed.
There's a second strict rule of `plug` command: every parameter that doesn't have a keyword before it, is treated as plugin configuration.
For example:

```kak
plug "andreyorst/fzf.kak" config %{
    map -docstring 'fzf mode' global normal '<c-p>' ': fzf-mode<ret>'
}
```

Here, `plug` will map <kbd>Ctrl</kbd>+<kbd>p</kbd> key only if the plugin is installed.
Everything within the `config %{}` block is an ordinary kakscript.

The `config` keyword is optional, and can be skipped.
Multiple `config` blocks are also supported.


### Deferring plugin configuration

With the introduction of the module system, some configurations have to be preformed after loading the module.
The `defer` keyword is a shorthand to register a `ModuleLoaded` hook for given `module`.

Below is the configuration of [fzf.kak](https://github.com/andreyorst/fzf.kak) plugin, which provides the `fzf` module:

```kak
plug "andreyorst/fzf.kak" config %{
    map -docstring 'fzf mode' global normal '<c-p>' ': fzf-mode<ret>'
} defer fzf %{
    set-option global fzf_preview_width '65%'
    set-option global fzf_project_use_tilda true
}
```

**Note**: the `ModuleLoaded` hook is defined as early as possible - before sourcing any of plugin files.

### Demanding plugin module configuration

Works the same as `defer` except requires the module immediately:

```kak
plug "andreyorst/fzf.kak" config {
    # evaluated before demanding the module
} demand fzf %{
    set-option global fzf_project_use_tilda true
} config %{
    # evaluated after demanding the module
}
```

The above snippet is a shorthand for this code:

``` kak
plug "andreyorst/fzf.kak" defer fzf %{
    set-option global fzf_project_use_tilda true
} config %{
    # evaluated before demanding the module
    require-module fzf
    # evaluated after demanding the module
}
```

**Note**: the `ModuleLoaded` hook is defined as early as possible - before sourcing any of plugin files.
The place where `require-module` call will be placed depends on the order of config blocks in the `plug` command.


## **plug.kak** Configuration

Several configuration options are available:

- Changing the [plugin installation directory](#plugin-installation-directory),
- Limiting the [maximum amount of active downloads](#maximum-downloads),
- Specifying the [default git domain](#default-git-domain),
- And [ensuring that plugins are installed](#ensuring-that-plugins-are-installed).

Proper way to configure **plug.kak** is to load it with the `plug` command, and providing both `noload` and `config` blocks:
This should be done before loading other plugins.

```kak
plug "andreyorst/plug.kak" noload config %{
    # configure plug.kak here
}
```


### Plugin installation directory

By default **plug.kak** automatically detects its installation path and installs plugins to the same directory.
To change this, use the `plug_install_dir` option:

```kak
plug "andreyorst/plug.kak" noload config %{
    set-option global plug_install_dir %sh{ echo $HOME/.cache/kakoune_plugins }
}
```


### Maximum downloads

**plug.kak** downloads plugins from github.com asynchronously via `git`.
By default it allows only `10` simultaneously active `git` processes.
To change this, use the `plug_max_simultaneous_downloads` option.


### Default git domain

If majority of plugins is installed from the service other than GitHub, default git domain can be changed to avoid specifying the `domain` keyword for each plugin, or using URLs.


## Commands

**plug.kak** adds five new commands to Kakoune.


### `plug-install`

This command installs all plugins that were specified in any of the configuration files sourced after Kakoune launch.
It accepts optional argument, which can be the plugin name or the URL, so it could be used to install a plugin from command prompt without restarting Kakoune.
This plugin will be enabled automatically, but you still need to add `plug` command to your configuration files in order to use that plugin after the restart.


### `plug-list`

Display the buffer with all installed plugins, and check for updates.
The <kbd>Enter</kbd> key is remapped to execute `plug-update` or `plug-install` command for selected plugin, depending on its state.
This command accepts an optional argument `noupdate`, and if it is specified, check for updates will not be performed.


### `plug-update`

This command updates all installed plugins.
It accepts one optional argument, which is a plugin name, so it could be used to update single plugin.
When called from prompt, it shows all installed plugins in the completion menu.


### `plug-clean`

Remove plugins, that are installed, but disabled or missing in configuration files.
This command also accepts optional argument, which is a plugin name, and can be used to remove any installed plugin.


### `plug`

Load plugin from plugin installation directory by its name.

[1]: https://img.shields.io/github/issues/andreyorst/plug.kak.svg
[2]: https://github.com/andreyorst/plug.kak/issues
[3]: https://img.shields.io/github/license/andreyorst/plug.kak.svg
[4]: https://user-images.githubusercontent.com/19470159/51197223-f2c26a80-1901-11e9-9494-b79ce823a364.png
[5]: https://github.com/junegunn/vim-plug
[6]: https://github.com/jwiegley/use-package
[8]: https://github.com/andreyorst/plug.kak

<!--  LocalWords:  kak Kakoune Kakoune's GitLab Gitea noload config
      LocalWords:  kakscript kbd Ctrl github fzf
 -->
