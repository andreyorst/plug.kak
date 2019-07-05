# plug.kak
[![GitHub issues][1]][2] ![license][3]

![plug.kak][4]

**plug.kak** is a plugin manager for Kakoune editor, that was inspired by
[vim-plug][5] and [use-package][6]. It helps installing and updating plugins,
can run post-update actions, and isolates plugin configuration within itself.

The release model of **plug.kak** supports one latest stable release of Kakoune, and
the development version. Default branch is always in sync with latest stable
release of Kakoune. If you're using Kakoune builds from GitHub repository,
please switch to [dev][7] branch.

## Installation
**plug.kak** can be installed anywhere in your system, but to manage itself
along with other plugins it requires to be installed in the same place where
other plugins are.  By default, **plug.kak** installs plugins to your
`%val{config}/plugins`. You can install **plug.kak** there, or elsewhere, and
change the `%opt{plug_install_dir}` option accordingly.

From now on, I'm assuming that you've decided to install **plug.kak** to the
default configuration directory. First, we need a directory for plugins:

```sh
mkdir -p ~/.config/kak/plugins/
```

After directory was created, we need to clone [plug.kak repository][8] there with this
command:

```sh
git clone https://github.com/andreyorst/plug.kak.git ~/.config/kak/plugins/plug.kak
```

Now, when **plug.kak** is installed, we need to tell Kakoune about it. You can
either symlink `plug.kak` file to your `autoload` directory, or use Kakoune `source`
command. I've added this `source` command to my `kakrc`:

```kak
source "%val{config}/plugins/plug.kak/rc/plug.kak"
```

As I've already mentioned **plug.kak** can work from any directory, but if you
installed it to your plugin installation directory, **plug.kak** will be able to
update itself along with another plugins.

Now you can use **plug.kak**.

## Usage
You can specify what plugins to install and load by using `plug` command. This
command accepts one-or-more arguments, which are keywords and attributes, that
change how **plug.kak** behaves.

The first strict rule of the `plug` command is that the first argument is always
the plugin name formatted as in GitHub URL: `"author/repository"`.

```kak
plug "author/repository"
```

By default **plug.kak** will look for this plugin at GitHub.com, and download it
for you.  If you want to install plugin from place other than GitHub, like
GitLab or Gitea, `plug` also accepts URL as first parameter.  So in most cases
it is enough to add this into your `kakrc` to use a plugin:

```kak
plug "delapouite/kakoune-text-objects"
```

Or with URL:

```kak
plug "https://gitlab.com/Screwtapello/kakoune-inc-dec"
```

You also can use different git domain by setting it with the
[`plug_git_domain`][16] option.

After adding this, you need to either re-source your `kakrc` or restart Kakoune
to let **plug.kak** know that configuration was changed. After that you can use
`plug-install` command to install new plugins. More information about other
commands available in [Commands](#Commands) section.

Now let's discuss what `plug` command can do.

### Keywords and attributes
As was already mentioned `plug` command accepts optional attributes, that change
how **plug.kak** works, or add additional steps for `plug` to perform for you.

These are available keywords:
- [branch, tag, commit][9]
- [load][10]
- [noload][11]
- [do][12]
- [theme][13]
- [config][14]
- [defer][21]
- [depth-sort][19] and [no-depth-sort][19]
- [domain][20]
- [ensure][15]

#### Branch, Tag or Commit
`plug` can checkout a plugin to desired branch, commit or tag before loading
it. To do so, add this after plugin name: `branch "branch_name"`, `tag
"tag_name"` or `commit "commit_hash"`.

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

Filenames must be specified one per line.

#### Skipping loading of a plugin
Sometimes plugin should be installed, but not loaded until certain event.  In
such case use `noload` attribute to skip loading of installed plugin. Useful
with plug.kak itself, because it is already loaded by user configuration.

```kak
plug "andreyorst/plug.kak" noload
```

However, not loading the plugin itself doesn't mean that `plug` command will
ignore plugin configuration. We'll discuss what this means later in the
[handling-user-configuration][14] section.

#### Automatically do certain tasks on install or update
Some plugins require compilation. Some plugins require to perform another task
on each update, or installation. For that **plug.kak** offers the `do` keyword,
that executes shell code after successful update of plugin or a fresh
installation of one. Useful for plugins that need to compile some parts of it.

```kak
plug "ul/kak-lsp" do %{
    cargo build --release --locked
    cargo install --force --path .
}
```

In this example **plug.kak** will run these `cargo` commands after `kak-lsp` was
updated, keeping the compiled part in sync with the `kakscript` part shipped
with the `kak-lsp` plugin.

#### Installing color schemes
**plug.kak** is capable of installing color schemes. Basically, the color scheme
in Kakoune is an ordinary kakscript, which we call with `color-scheme`
command. That means that we don't need to load themes shipped with the plugin.
To tell `plug` command that plugin is a color-scheme, the `theme` switch should
be used.  **plug.kak** will copy color scheme files to the `colors` directory
located at `%val{config}/colors`. For example:

```kak
plug "alexherbo2/kakoune-dracula-theme" theme

plug "andreyorst/base16-gruvbox.kak" theme config %{
    colorscheme base16-gruvbox-dark-soft
}
```

Here we install two themes, the `kakoune-dracula-theme` and a set of
`base16-gruvbox` themes. We specify that these plugins are themes, and then tell
`plug` that we want to set our theme to `base16-gruvbox-dark-soft` within the
`config` block.

#### Depth sorting sourced files
Some plugins (ahem, my plugins) sometimes use module structure, that is based on
depth. What this means is that if plugin declares a modules, it does it deeper
in file tree. For example, if main script is placed in `rc/plugin.kak` then
modules will be declared in `rc/modules/module.kak`. If module uses something
that is prepared by base script it's logical to `source` it first. But `find`
program, that is used to get list of plugin files can return them in any
order. For that **plug.kak** provides `perl` based depth-sorting algorithm. It
adds a bit of overhead, but can save the day sometimes. You can enable it for
all plugins with `plug_depth_sort` option set to `true`, and on per-plugin basis
by using `depth-sort` attribute of `plug` command:

```kak
plug "andreyorst/fzf.kak" depth-sort
plug "andreyorst/powerline.kak" no-depth-sort
```

Disabling depth-sorting on per-plugin is available with `no-depth-sort`
attribute.

#### Specifying Git domain on per-plugin basis
When you want to install plugin from a domain that is different from your
`%opt{plug_git_domain}` you may use two different methods. First one is to pass
URL directly to `plug` command like so:

```kak
plug "https://gitlab.com/screwtapello/kakoune-inc-dec.git"
plug "https://bitbucket.org/KJ_Duncan/kakoune-kotlin.kak.git"
```

The other is essentially the same, but I find it prettier, and it looks better
in `plug-list` output:

```kak
plug "screwtapello/kakoune-inc-dec" domain "gitlab.com"
plug "KJ_Duncan/kakoune-kotlin.kak" domain "bitbucket.org"
```

#### Ensure that plugins are installed
`plug` command can be explicitly told to install the plugin on loading with the
`ensure` keyword. This is handy in case you don't isolated the configuration of
the plugin, so you want this plugin to be installed and enabled in any
situation.

You also can configure **plug.kak** `plug_always_ensure` option to perform this
for each and every plugin in your configuration file. This is handy when you
want to install new plugins without calling the `plug-install` command.

Now, let's discuss configuration of plugins with `plug` command.

#### Handling user configurations
Common problem with plugin configuration, and a configuration of external
features in general, is that when this feature is not available, the
configuration makes no sense at all.

Previously I've mentioned that [`noload`][11] switch doesn't affect the
configuration process of a plugin. That is, the configuration isn't loaded only
when plugin is not installed. Which means that if you decide to install your
configuration to a new machine, Kakoune won't throw errors that something isn't
available, for example some plugin options.

There's second strict rule of `plug` command: every parameter that doesn't have
a keyword before it, is treated as plugin configuration.

For example:

```kak
plug "andreyorst/fzf.kak" config %{
    map -docstring 'fzf mode' global normal '<c-p>' ': fzf-mode<ret>'
}
```

In this example I'm setting a <kbd>Ctrl</kbd>+<kbd>p</kbd> mapping that is
meaningful only if the plugin is installed. I've could configure it outside of
`plug` command, but it will fail if I accidentally remove or disable the
plugin. In case of configuring it with `plug` command, I don't need to keep
track of other configuration pieces. Everything within the `config %{ }` block
is ordinary kakscript.

The `config` keyword is optional, you can skip it if you want. Multiple `config`
blocks are supported as well.

### Deferring plugin configuration
Sometimes it is unnecessary to configure plugin if it isn't loaded. Since
Kakoune added support for module system with `provide-module` and
`require-module` followed by `ModuleLoaded` hook it is possible to defer
configuration until certain module is loaded. For example, let's look on
`fzf.kak` configuration deferred until `fzf` module is required:

```kak
plug "andreyorst/fzf.kak" config %{
    map -docstring 'fzf mode' global normal '<c-p>' ': fzf-mode<ret>'
} defer "fzf" %{
    set-option global fzf_preview_width '65%'
    set-option global fzf_project_use_tilda true
    evaluate-commands %sh{
        if [ -n "$(command -v fd)" ]; then
            echo "set-option global fzf_file_command %{fd . --no-ignore --type f --follow --hidden --exclude .git --exclude .svn}"
        else
            echo "set-option global fzf_file_command %{find . \( -path '*/.svn*' -o -path '*/.git*' \) -prune -o -type f -follow -print}"
        fi
        [ -n "$(command -v bat)" ] && echo "set-option global fzf_highlight_cmd bat"
        [ -n "${kak_opt_grepcmd}" ] && echo "set-option global fzf_sk_grep_command %{${kak_opt_grepcmd}}"
    }
}
```

The `defer "fzf" %{ ... }` block is a configuration block that will be evaluated
only when `fzf` module is loaded.

Since we've touched the configuration of **plug.kak** itself, let's discuss this
topic.

## **plug.kak** Configuration
You can change some bits of **plug.kak** behavior:
- Change [plugin installation directory][16]
- Limit the [maximum amount of active downloads][17]
- Specify [default git domain][18]
- And already mentioned, [Ensure that plugins are installed][15] and [Depth sorting][19]

To change these options, I'm recommending to call **plug.kak** before all
plugins with the `plug` command, specified with `noload` switch and `config`
keyword like so:

```kak
# source plug.kak script
source "%val{config}/plugins/plug.kak/rc/plug.kak"

# call plug.kak with `plug' command
plug "andreyorst/plug.kak" noload config %{
    # configure plug.kak here
}
```

This means that **plug.kak** was installed in the plugin installation directory.

### Plugin installation directory

You can specify where to install plugins, in case you don't like default
`~/.config/kak/plugins/` path. You can do so by changing `plug_install_dir` option:
(note: if you want to use environment variables in the path, consider using shell expansion like in this example)

```kak
plug "andreyorst/plug.kak" noload config %{
    set-option global plug_install_dir %sh{ echo $HOME/.cache/kakoune_plugins }
}
```

**plug.kak** will download plugins to that directory. Speaking of downloads.

### Maximum downloads
**plug.kak** downloads plugins from the github.com asynchronously in the
background. By default it allows only `10` simultaniously active downloads. To
allow more, or less downloads at the same time you can change
`plug_max_simultaneous_downloads` option.

### Default git domain
Although you can use URLs inside `plugin` field, if you're using plugins from,
say, Gitlab only, using URLs is tedious. You and set default git domain to
`https://gitlab.com`, or to any other git domain, as long as it
similar to github's in term of URL structure, and use `"author/repository"`
instead of URL in `plug` command.

I've mentioned that `plug` is a command. Indeed you can call `plug` from the
Kakoune command prompt, as long as other **plug.kak** commands.

## Commands
**plug.kak** adds five new commands to Kakoune. I wanted to make it simple, so
commands are pretty much self explained by their names, but there are some notes
that I still need to mention.

### `plug-install`
This command installs all plugins that were specified in any configuration
file. It accepts optional argument, which is plugin name or URL, so it could be
used to install plugin from command prompt without restarting Kakoune. This
plugin will be enabled automatically, but you still need to add `plug` command
to your configuration files in order to use that plugin after the restart.

### `plug-update`
This commands updates all installed plugins. It accepts one optional argument,
which is a plugin name, so it could be used to update single plugin. When called
from prompt, it shows all installed plugins in the completion menu. This command
is used by default with the <kbd>Enter</kbd> key on any plugin that is installed
in the `*plug*` buffer.

### `plug-clean`
Remove plugins, that are installed, but disabled or missing in configuration
files. This command also accepts optional argument, which is a plugin name, and
can be used to remove any installed plugin.

### `plug-list`
This command can be used to manually invoke the `*plug*` buffer. In this buffer
all installed plugins are listed, and checked for updates. The <kbd>Enter</kbd>
key is remapped to execute `plug-update` or `plug-install` command for selected
plugin, depending on its state. This command accepts an optional argument
`noupdate`, and if it is specified, check for updates will not be performed.

### `plug`
And last but not least: `plug`. Load plugin from plugin installation directory by its name.

[1]: https://img.shields.io/github/issues/andreyorst/plug.kak.svg
[2]: https://github.com/andreyorst/plug.kak/issues
[3]: https://img.shields.io/github/license/andreyorst/plug.kak.svg
[4]: https://user-images.githubusercontent.com/19470159/51197223-f2c26a80-1901-11e9-9494-b79ce823a364.png
[5]: https://github.com/junegunn/vim-plug
[6]: https://github.com/jwiegley/use-package
[7]: https://github.com/andreyorst/plug.kak/tree/dev
[8]: https://github.com/andreyorst/plug.kak

[9]: #Branch-Tag-or-Commit
[10]: #Loading-subset-of-files-from-plugin-repository
[11]: #Skipping-loading-of-a-plugin
[12]: #Automatically-do-certain-tasks-on-install-or-update
[13]: #Installing-color-schemes
[14]: #Handling-user-configurations
[15]: #Ensuring-that-plugin-is-installed

[16]: #Plugin-installation-directory
[17]: #Maximum-downloads
[18]: #Default-git-domain
[19]: #Depth-sorting-sourced-files
[20]: #Specifying-git-domain-on-per-plugin-basis
[21]: #Deferring-plugin-configuration
