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

declare-option -docstring "path where plugins should be installed.\nDefault value: '$HOME/.config/kak/plugins'" \
    str plug_install_dir '$HOME/.config/kak/plugins'
declare-option -hidden str plug_plugins ''
declare-option -hidden str plug_loaded_plugins

hook global WinSetOption filetype=kak %{
    add-highlighter window/plug regex ^(\h+)?\bplug\b 0:keyword
}

define-command -override -hidden -docstring "
plug <username/reponame>
" \
plug -params 1.. %{
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
                    if [ -z "${arg##*branch*}" ]; then
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

# TODO:
# Find a way to measure amount of simultaneously running Git processes
# to run not more than 5 at once, and let user configure this amount
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
define-command -override -docstring 'Update all installed plugins' \
plug-update %{
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
