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
"Maximum amount of simultaneous downloads when installing or updating plugins
    Default value: 10
" \
int plug_max_simultaneous_downloads 10

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

define-command -override -docstring \
"plug <plugin> [<branch>]: load <plugin> from ""%opt{plug_install_dir}""
" \
plug -params 1.. -shell-candidates %{ ls -1 $(eval echo $kak_opt_plug_install_dir) } %{
	set-option -add global plug_plugins "%arg{1} "
	evaluate-commands %sh{
		loaded=$(eval echo $kak_opt_plug_loaded_plugins)
		if [ ! -z "$loaded" ] && [ -z "${loaded##*$1*}" ]; then
			printf %s\\n "evaluate-commands -client $kak_client echo -markup '{Information}${1##*/} already loaded'" | kak -p ${kak_session}
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

define-command -override -docstring 'Install all plugins mentioned in configuration files' \
plug-install %{
	echo -markup "{Information}Installing plugins in the background"
	nop %sh{ (
		if [ -d $(eval echo "$kak_opt_plug_install_dir/.plug.kaklock") ]; then
			printf %s\\n "evaluate-commands -client $kak_client echo -markup '{Information}.plug.kaklock is present. Waiting...'" | kak -p ${kak_session}
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
		printf %s\\n "evaluate-commands -client $kak_client echo -markup '{Information}Done installing plugins'" | kak -p ${kak_session}
	) >/dev/null 2>&1 < /dev/null & }
}

define-command -override -docstring \
"plug-update [<plugin>]: Update plugin.
If <plugin> ommited all installed plugins are updated" \
plug-update -params ..1 -shell-candidates %{ echo $kak_opt_plug_plugins | tr ' ' '\n' } %{
	nop %sh{ (
		plugin=$1
		if [ -d $(eval echo "$kak_opt_plug_install_dir/.plug.kaklock") ]; then
			printf %s\\n "evaluate-commands -client $kak_client echo -markup '{Information}.plug.kaklock is present. Waiting...'" | kak -p ${kak_session}
		fi
		while ! mkdir $(eval echo "$kak_opt_plug_install_dir/.plug.kaklock") 2>/dev/null; do sleep 1; done
		trap 'rmdir $(eval echo "$kak_opt_plug_install_dir/.plug.kaklock")' EXIT
		if [ ! -z $plugin ]; then
			if [ -d $(eval echo $kak_opt_plug_install_dir/"${plugin##*/}") ]; then
				printf %s\\n "evaluate-commands -client $kak_client echo -markup '{Information}Updating $plugin'" | kak -p ${kak_session}
				(cd $(eval echo $kak_opt_plug_install_dir/"${plugin##*/}") && git pull >/dev/null 2>&1) &
			else
				printf %s\\n "evaluate-commands -client $kak_client echo -markup '{Error}can''t update $plugin. Plugin is not installed'" | kak -p ${kak_session}
				exit
			fi
		else
			printf %s\\n "evaluate-commands -client $kak_client echo -markup '{Information}Updating plugins in the background'" | kak -p ${kak_session}
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
		printf %s\\n "evaluate-commands -client $kak_client echo -markup '{Information}Done updating plugins'" | kak -p ${kak_session}
	) > /dev/null 2>&1 < /dev/null & }
}

define-command -override -docstring "plug-delete [<plugin>]: delete <plugin>.
If <plugin> ommited deletes all plugins that are not presented in configuration files" \
plug-clean -params ..1 -shell-candidates %{ ls -1 $(eval echo $kak_opt_plug_install_dir) } %{
	nop %sh{ (
		plugin=$1
		if [ -d $(eval echo "$kak_opt_plug_install_dir/.plug.kaklock") ]; then
			printf %s\\n "evaluate-commands -client $kak_client echo -markup '{Information}.plug.kaklock is present. Waiting...'" | kak -p ${kak_session}
		fi
		while ! mkdir $(eval echo "$kak_opt_plug_install_dir/.plug.kaklock") 2>/dev/null; do sleep 1; done
		trap 'rmdir $(eval echo "$kak_opt_plug_install_dir/.plug.kaklock")' EXIT

		if [ ! -z $plugin ]; then
			if [ -d $(eval echo $kak_opt_plug_install_dir/"${plugin##*/}") ]; then
				(cd $(eval echo $kak_opt_plug_install_dir) && rm -rf "${plugin##*/}")
				printf %s\\n "evaluate-commands -client $kak_client echo -markup '{Information}Removed $plugin'" | kak -p ${kak_session}
			else
				printf %s\\n "evaluate-commands -client $kak_client echo -markup '{Error}No such plugin $plugin'" | kak -p ${kak_session}
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
