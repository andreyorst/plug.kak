declare-option -docstring "path where plugins should be installed" \
	str plug_install_dir '$HOME/.config/kak/plugins'
declare-option -hidden -docstring "Array of plugins" \
	str plug_plugins ''

define-command -hidden plug -params 1..2 %{
	evaluate-commands %sh{
		if [ -d $(eval echo $kak_opt_plug_install_dir) ]; then
			if [ -d $(eval echo $kak_opt_plug_install_dir/"${1##*/}") ]; then
				for file in $(find -L $(eval echo $kak_opt_plug_install_dir/"${1##*/}") -type f -name '*.kak'); do
					[ "${file##*/}" != "plug.kak" ] && echo source "$file"
				done
			fi
		fi
	}
	set-option -add global plug_plugins %arg{1}
	set-option -add global plug_plugins " "
}

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
				(cd $(eval echo $kak_opt_plug_install_dir); git clone https://github.com/$plugin >/dev/null 2>&1) &
			fi
		done
		wait

		printf %s\\n "evaluate-commands -client $kak_client echo -markup '{Information}Done installing plugins'" | kak -p ${kak_session}
	) >/dev/null 2>&1 < /dev/null & }
}

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

		for instlled_plugin in $(echo $(eval echo $kak_opt_plug_install_dir)/*); do
			skip=
			for enabled_plugin in $kak_opt_plug_plugins; do
				[ "${instlled_plugin##*/}" = "${enabled_plugin##*/}" ] && { skip=1; break; }
			done
			[ "$skip" = "1" ] || plugins_to_remove+=("$instlled_plugin")
		done
		for plugin in ${plugins_to_remove[*]}; do
			rm -rf $plugin
		done
	) > /dev/null 2>&1 < /dev/null & }
}
