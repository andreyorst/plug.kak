# ╭─────────────╥──────────╥─────────╮
# │ Author:     ║ File:    ║ Branch: │
# │ Andrey Orst ║ plug.kak ║ master  │
# ╞═════════════╩══════════╩═════════╡
# │ plug.kak is a plugin manager for │
# │ Kakoune. It can install plugins  │
# │ keep them updated and uninstall  │
# ╞══════════════════════════════════╡
# │ GitHub repo:                     │
# │ GitHub.com/andreyorst/plug.kak   │
# ╰──────────────────────────────────╯

declare-option -docstring \
"path where plugins should be installed.

    Default value: '$HOME/.config/kak/plugins'
" \
str plug_install_dir '$HOME/.config/kak/plugins'

declare-option -docstring \
"default domain to access git repositories. Can be changed to any preferred domain, like gitlab, bitbucket, gitea, etc.

    Default value: 'https://github.com'
" \
str plug_git_domain 'https://github.com'

declare-option -docstring \
"Maximum amount of simultanious downloads when installing or updating plugins
    Default value: 6
" \
int plug_max_simultanious_downloads 6

# Since plug.kak can and should be reloaded with main Kakoune configuration,
# we need to clear known plugins in order track if some plugins were disabled
declare-option -hidden str plug_plugins ''
# List of loaded plugins should not pe cleared during update of configuration files.
declare-option -hidden str plug_loaded_plugins

hook global WinSetOption filetype=kak %{
	add-highlighter window/plug regex ^(\h+)?\bplug\b 0:keyword
}

define-command -override -hidden plug -params 1.. %{
	set-option -add global plug_plugins "%arg{1} "
	evaluate-commands %sh{
		loaded="_ "$(eval echo $kak_opt_plug_loaded_plugins)
		if [ -z "${loaded##*$1*}" ]; then
			eval echo "echo -markup '{Information}$1 already loaded. Skipping'"
			exit
		fi

		if [ -d $(eval echo $kak_opt_plug_install_dir) ]; then
			if [ -d $(eval echo $kak_opt_plug_install_dir/"${1##*/}") ]; then
				eval echo 'set-option -add global plug_loaded_plugins \"$1 \"'
				for arg in "$@"; do
					if [ -z "${arg##*branch*}" ]  || [ -z "${arg##*tag*}" ]; then
						branch=$(echo $arg | awk '{print $2}')
						(cd $(eval echo $kak_opt_plug_install_dir/"${1##*/}"); git checkout $branch >/dev/null 2>&1)
						break
					fi
				done
				[ "$1" = "andreyorst/plug.kak" ] && exit
				for file in $(find -L $(eval echo $kak_opt_plug_install_dir/"${1##*/}") -type f -name '*.kak'); do
					echo source "$file"
				done
			fi
		fi
	}
}

define-command -override -docstring 'Install all uninstalled plugins' \
plug-install %{
	echo -markup "{Information}Installing plugins in the background"
	nop %sh{ (
		while ! mkdir .plug.kaklock 2>/dev/null; do sleep 1; done
			trap 'rmdir .plug.kaklock' EXIT

		if [ ! -d $(eval echo $kak_opt_plug_install_dir) ]; then
			mkdir -p $(eval echo $kak_opt_plug_install_dir)
		fi

		for plugin in $kak_opt_plug_plugins; do
			case $plugin in
				http*|git*)
					git="git clone $plugin" ;;
				*)
					git="git clone $kak_opt_plug_git_domain/$plugin" ;;
			esac
			if [ ! -d $(eval echo $kak_opt_plug_install_dir/"${plugin##*/}") ]; then
				(cd $(eval echo $kak_opt_plug_install_dir); $git >/dev/null 2>&1) &
			fi
			printf %s\\n "evaluate-commands -client $kak_client echo -markup '{Information}$(jobs | wc -l) active downloads'" | kak -p ${kak_session}
			while [ `jobs | wc -l` -ge $kak_opt_plug_max_simultanious_downloads ]; do
				sleep 1
			done
		done
		wait

		printf %s\\n "evaluate-commands -client $kak_client echo -markup '{Information}Done installing plugins'" | kak -p ${kak_session}
	) >/dev/null 2>&1 < /dev/null & }
}

# TODO: same as for plug-install
define-command -override -docstring 'Update all installed plugins' \
plug-update %{
	echo -markup "{Information}Updating plugins in the background"
	nop %sh{ (
		while ! mkdir .plug.kaklock 2>/dev/null; do sleep 1; done
			trap 'rmdir .plug.kaklock' EXIT

		for plugin in $kak_opt_plug_plugins; do
			(cd $(eval echo $kak_opt_plug_install_dir/"${plugin##*/}") && git pull >/dev/null 2>&1) &
			while [ "$(jobs | wc -l)" = "$kak_opt_plug_max_simultanious_downloads" ]; do
				sleep 1
			done
		done
		wait
		printf %s\\n "evaluate-commands -client $kak_client echo -markup '{Information}Done updating plugins'" | kak -p ${kak_session}
	) > /dev/null 2>&1 < /dev/null & }
}

define-command -override -docstring 'Delete all plugins that not present in config files' \
plug-clean %{
	nop %sh{ (
		while ! mkdir .plug.kaklock 2>/dev/null; do sleep 1; done
			trap 'rmdir .plug.kaklock' EXIT

		for installed_plugin in $(echo $(eval echo $kak_opt_plug_install_dir)/*); do
			skip=
			for enabled_plugin in $kak_opt_plug_plugins; do
				[ "${installed_plugin##*/}" = "${enabled_plugin##*/}" ] && { skip=1; break; }
			done
			[ "$skip" = "1" ] || plugins_to_remove=$plugins_to_remove" $installed_plugin"
		done
		for plugin in $plugins_to_remove; do
			# dangerous way to do this, but I don't know a better way to check
			# if processed folder is really a plugin
			rm -rf $plugin
		done
	) > /dev/null 2>&1 < /dev/null & }
}
