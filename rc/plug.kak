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
    Default value: 5
" \
int plug_max_simultanious_downloads 5

declare-option -hidden -docstring \
"Array of all plugins, mentioned in any configuration file.
Empty by default, and erased on reload of main Kakoune configuration, to track if some plugins were disabled
Shlould not be modified by user." \
str plug_plugins ''

declare-option -hidden -docstring \
"List of loaded plugins. Has no default value.
Should not be cleared during update of configuration files. Shluld not be modified by user." \
str plug_loaded_plugins

hook global WinSetOption filetype=kak %{
	add-highlighter window/plug regex ^(\h+)?\bplug\b\h 0:keyword
}

define-command -override -hidden plug -params 1.. -shell-candidates %{ ls -1 $(eval echo $kak_opt_plug_install_dir) } %{
	set-option -add global plug_plugins "%arg{1} "
	evaluate-commands %sh{
		loaded=$(eval echo $kak_opt_plug_loaded_plugins)
		if [ ! -z "$loaded" ] && [ -z "${loaded##*$1*}" ]; then
			eval echo "echo -markup '{Information}${1##*/} already loaded'"
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
	evaluate-commands %sh{ (
		if [ -d $(eval echo "$kak_opt_plug_install_dir/.plug.kaklock") ]; then
			echo "echo -markup '{Information}.plug.kaklock is present. Waiting...'"
		fi
		while ! mkdir $(eval echo "$kak_opt_plug_install_dir/.plug.kaklock") 2>/dev/null; do sleep 1; done
		trap 'rmdir $(eval echo "$kak_opt_plug_install_dir/.plug.kaklock")' EXIT

		if [ ! -d $(eval echo $kak_opt_plug_install_dir) ]; then
			mkdir -p $(eval echo $kak_opt_plug_install_dir)
		fi

		jobs=$(mktemp /tmp/jobs.XXXXXX)
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
			jobs > $jobs; active=$(wc -l < $jobs)
			while [ $active -ge 2 ]; do
				sleep 1
				jobs > $jobs; active=$(wc -l < $jobs)
			done
		done
		wait
		rm -rf $jobs
		echo "echo -markup '{Information}Done installing plugins'"
	) >/dev/null 2>&1 < /dev/null & }
}

define-command -override -docstring 'Update all installed plugins' \
plug-update -params ..1 -shell-candidates %{ echo $kak_opt_plug_plugins | tr ' ' '\n' } %{
	evaluate-commands %sh{ (
		plugin=$1
		if [ -d $(eval echo "$kak_opt_plug_install_dir/.plug.kaklock") ]; then
			echo "echo -markup '{Information}.plug.kaklock is present. Waiting...'"
		fi
		while ! mkdir $(eval echo "$kak_opt_plug_install_dir/.plug.kaklock") 2>/dev/null; do sleep 1; done
		trap 'rmdir $(eval echo "$kak_opt_plug_install_dir/.plug.kaklock")' EXIT
		if [ ! -z $plugin ]; then
			if [ -d $(eval echo $kak_opt_plug_install_dir/"${plugin##*/}") ]; then
				eval echo "echo -markup '{Information}Updating $plugin'"
				(cd $(eval echo $kak_opt_plug_install_dir/"${plugin##*/}") && git pull >/dev/null 2>&1) &
			else
				echo "echo -markup '{Error}can''t update $plugin. Plugin is not installed'"
				exit
			fi
		else
			echo "echo -markup '{Information}Updating plugins in the background'"
			jobs=$(mktemp /tmp/jobs.XXXXXX)
			for plugin in $kak_opt_plug_plugins; do
				(cd $(eval echo $kak_opt_plug_install_dir/"${plugin##*/}") && git pull >/dev/null 2>&1) &
				jobs > $jobs; active=$(wc -l < $jobs)
				while [ $active -ge 2 ]; do
					sleep 1
					jobs > $jobs; active=$(wc -l < $jobs)
				done
			done
			rm -rf $jobs
		fi
		wait
		echo "echo -markup '{Information}Done updating plugins'"
	) > /dev/null 2>&1 < /dev/null & }
}

define-command -override -docstring 'Delete all plugins that not present in config files' \
plug-clean -params ..1 -shell-candidates %{ ls -1 $(eval echo $kak_opt_plug_install_dir) } %{
	evaluate-commands %sh{ (
		plugin=$1
		if [ -d $(eval echo "$kak_opt_plug_install_dir/.plug.kaklock") ]; then
			echo "echo -markup '{Information}.plug.kaklock is present. Waiting...'"
		fi
		while ! mkdir $(eval echo "$kak_opt_plug_install_dir/.plug.kaklock") 2>/dev/null; do sleep 1; done
		trap 'rmdir $(eval echo "$kak_opt_plug_install_dir/.plug.kaklock")' EXIT

		if [ ! -z $plugin ]; then
			if [ -d $(eval echo $kak_opt_plug_install_dir/"${plugin##*/}") ]; then
				(cd $(eval echo $kak_opt_plug_install_dir) && rm -rf "${plugin##*/}")
				eval echo "echo -markup '{Information}Removed $plugin'"
			else
				echo "echo -markup '{Error}No such plugin $plugin'"
				exit
			fi
		else
			for installed_plugin in $(echo $(eval echo $kak_opt_plug_install_dir)/*); do
				skip=
				for enabled_plugin in $kak_opt_plug_plugins; do
					[ "${installed_plugin##*/}" = "${enabled_plugin##*/}" ] && { skip=1; break; }
				done
				[ "$skip" = "1" ] || plugins_to_remove=$plugins_to_remove" $installed_plugin"
			done
			for plugin in $plugins_to_remove; do
				rm -rf $plugin
			done
		fi
	) > /dev/null 2>&1 < /dev/null & }
}
