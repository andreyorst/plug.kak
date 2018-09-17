declare-option -docstring "path where plugins should be installed.\nDefault value: '$HOME/.config/kak/plugins'" \
	str plug_install_dir '$HOME/.config/kak/plugins'
declare-option -hidden -docstring "Array of plugins. Should not be modified by user" \
	str plug_plugins ''

# since Kakoune escapes shell symbols in options
# eval is used in many places of this script
# to get actual value of Kakoune options
define-command -hidden plug -params 1..2 %{
	evaluate-commands %sh{
		if [ -d $(eval echo $kak_opt_plug_install_dir) ]; then
			if [ -d $(eval echo $kak_opt_plug_install_dir/"${1##*/}") ]; then
				for file in $(find -L $(eval echo $kak_opt_plug_install_dir/"${1##*/}") -type f -name '*.kak'); do
					# rough way to not load plug when plug command is used with plug.kak as a parameter
					[ "${file##*/}" != "plug.kak" ] && echo source "$file"
				done
			fi
		fi
	}
	# rough way to keep installed plugins
	set-option -add global plug_plugins %arg{1}
	# since I don't know how concatenate strings, I just add space to current option every time
	set-option -add global plug_plugins " "
}

# TODO:
# Find a way to measure amount of simultaneously running Git processes
# to run not more than 5 at once, and let user configure this amount
define-command plug-install -docstring 'Install all uninstalled plugins' %{
	echo -markup "{Information}Installing plugins in the background"
	nop %sh{ (
		while ! mkdir .plug.kaklock 2>/dev/null; do sleep 1; done
			trap 'rmdir .plug.kaklock' EXIT

		if [ ! -d $(eval echo $kak_opt_plug_install_dir) ]; then
			mkdir -p $(eval echo $kak_opt_plug_install_dir)
		fi

		for plugin in $kak_opt_plug_plugins; do
			if [ ! -d $(eval echo $kak_opt_plug_install_dir/"${plugin##*/}") ]; then
			# TODO: Support different git systems like gitlab, bitbucket
				(cd $(eval echo $kak_opt_plug_install_dir); git clone https://github.com/$plugin >/dev/null 2>&1) &
			fi
		done
		wait

		printf %s\\n "evaluate-commands -client $kak_client echo -markup '{Information}Done installing plugins'" | kak -p ${kak_session}
	) >/dev/null 2>&1 < /dev/null & }
}

# TODO: same as for plug-install
define-command plug-update -docstring 'Update all installed plugins' %{
	echo -markup "{Information}Updating plugins in the background"
	nop %sh{ (
		while ! mkdir .plug.kaklock 2>/dev/null; do sleep 1; done
			trap 'rmdir .plug.kaklock' EXIT

		for plugin in $kak_opt_plug_plugins; do
			(cd $(eval echo $kak_opt_plug_install_dir/"${plugin##*/}") && git pull >/dev/null 2>&1) &
		done
		wait
		printf %s\\n "evaluate-commands -client $kak_client echo -markup '{Information}Done updating plugins'" | kak -p ${kak_session}
	) > /dev/null 2>&1 < /dev/null & }
}

define-command plug-clean -docstring 'Delete all plugins that not present in config files' %{
	nop %sh{ (
		while ! mkdir .plug.kaklock 2>/dev/null; do sleep 1; done
			trap 'rmdir .plug.kaklock' EXIT

		for installed_plugin in $(echo $(eval echo $kak_opt_plug_install_dir)/*); do
			skip=
			for enabled_plugin in $kak_opt_plug_plugins; do
				[ "${installed_plugin##*/}" = "${enabled_plugin##*/}" ] && { skip=1; break; }
			done
			# hacky way to concatenate strings to iterate over them later
			[ "$skip" = "1" ] || plugins_to_remove=$plugins_to_remove" $installed_plugin"
		done
		for plugin in $plugins_to_remove; do
			# dangerous way to do this, but I don't know a better way to check
			# if processed folder is really a plugin
			rm -rf $plugin
		done
	) > /dev/null 2>&1 < /dev/null & }
}

