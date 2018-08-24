# plug.kak

**plug.kak** is a plugin manager for Kakoune editor, that aims to work somewhat
similar to [vim-plug](https://github.com/junegunn/vim-plug). It is being tested
against Kakoune v2018.04.13.

## Installation

``` sh
git clone https://github.com/andreyorst/plug.kak.git ~/.config/kak/plugins/
```

And source `plug.kak` from your `kakrc`, or any of your configuration file.

## Usage

You can specify what plugins to install and load by using `plug` command:

``` kak
plug github_username/repo_name
```

## Commands

**plug.kak** adds three commands:

- `plug-install` - Install all plugins specified in any configuration file
- `plug-update` - Update installed plugins
- `plug-clean` - Remove plugins, that are installed, but disabled in
  configuration files.

[Kakoune]: http://kakoune.org
[IRC]: https://webchat.freenode.net?channels=kakoune
[IRC Badge]: https://img.shields.io/badge/IRC-%23kakoune-blue.svg

