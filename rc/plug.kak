# ╭─────────────╥──────────╥─────────────╮
# │ Author:     ║ File:    ║ Branch:     │
# │ Andrey Orst ║ plug.kak ║ v2018.10.27 │
# ╞═════════════╩══════════╩═════════════╡
# │ plug.kak is a plugin manager for     │
# │ Kakoune. It can install plugins      │
# │ keep them updated and uninstall      │
# ╞══════════════════════════════════════╡
# │ GitHub repo:                         │
# │ GitHub.com/andreyorst/plug.kak       │
# ╰──────────────────────────────────────╯

evaluate-commands %sh{
    if [ "$kak_version" != "v2018.10.27" ]; then
        echo "echo -debug %{plug.kak: Warning Your Kakoune version doesn't match curren plug.kak version. please check if there is another release branch at https://github.com/andreyorst/plug.kak}"
    fi
}

declare-option -docstring \
"path where plugins should be installed.

    Default value: '%val{config}/plugins'
" \
str plug_install_dir "%val{config}/plugins"

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
Should not be modified by user." \
str plug_plugins ''

declare-option -hidden -docstring \
"List of loaded plugins. Has no default value.
Should not be cleared during update of configuration files. Shluld not be modified by user." \
str plug_loaded_plugins

declare-option -hidden -docstring \
"List of post update/install hooks to be executed" \
str plug_post_hooks ''

declare-option -hidden -docstring \
"List of configurations for all mentioned plugins" \
str plug_configurations ''

declare-option -docstring \
"enable or disable messages about per plugin load time to profile configuration" \
bool plug_profiler true

hook global WinSetOption filetype=kak %{ try %{
    add-highlighter window/plug        regex \bplug\b\h+((?=")|(?=')|(?=%)|(?=\w)) 0:keyword
    add-highlighter window/plug_do     regex \bdo\b\h+((?=")|(?=')|(?=%)|(?=\w)) 0:keyword
    add-highlighter window/plug_noload regex \bnoload\b 0:attribute
}}

hook  global WinSetOption filetype=(?!kak).* %{ try %{
    remove-highlighter window/plug
    remove-highlighter window/plug_do
    remove-highlighter window/plug_noload
}}

define-command -override -docstring \
"plug <plugin> [<branch>|<tag>|<commit>] [<noload>] [<configurations>]: load <plugin> from ""%opt{plug_install_dir}""
" \
plug -params 1.. -shell-script-candidates %{ ls -1 $(eval echo $kak_opt_plug_install_dir) } %{
    set-option -add global plug_plugins "%arg{1} "
    evaluate-commands %sh{
        start=$(expr $(date +%s%N) / 10000000)
        plugin=$1; shift
        noload=
        state=
        loaded=$(eval echo $kak_opt_plug_loaded_plugins)
        if [ ! -z "$loaded" ] && [ -z "${loaded##*$plugin*}" ]; then
            echo "echo -markup %{{Information}${plugin##*/} already loaded}"
            exit
        fi

        for arg in "$@"; do
            case $arg in
                "*branch:*"|"*tag:*"|"*commit:*")
                    branch=$(echo $arg | awk '{print $2}'); shift ;;
                "noload")
                    noload=1; shift ;;
                "do")
                    shift;
                    plug_opt=$(echo "${plugin##*/}" | sed 's:[^a-zA-Z0-9_]:_:g;')
                    echo "set-option -add global plug_post_hooks %{$plug_opt:$1┆}"
                    shift ;;
                *)
                    ;;
            esac
        done
        if [ $# -gt 0 ]; then
            plug_conf=$(echo "${plugin##*/}" | sed 's:[^a-zA-Z0-9_]:_:g;')
            echo "set-option -add global plug_configurations %{$plug_conf:$1┆}"
        fi

        if [ -d $(eval echo $kak_opt_plug_install_dir) ]; then
            if [ -d $(eval echo $kak_opt_plug_install_dir/"${plugin##*/}") ]; then
                if [ ! -z $branch ]; then
                    (cd $(eval echo $kak_opt_plug_install_dir/"${plugin##*/}"); git checkout $branch >/dev/null 2>&1)
                fi
                if [ -z $noload ]; then
                    for file in $(find -L $(eval echo $kak_opt_plug_install_dir/"${plugin##*/}") -type f -name '*.kak'); do
                        echo source "$file"
                    done
                fi
                if [ -z "${kak_opt_configurations##*$plug_conf*}" ]; then
                    if [ ! -z $noload ]; then
                        state=" (configuration)"
                        noload=
                    fi
                    echo "plug-configure $plugin"
                fi
                echo "set-option -add global plug_loaded_plugins %{$plugin }"
            else
                exit
            fi
        fi

        if [ -z $noload ]; then
            end=$(expr $(date +%s%N) / 10000000)
            message="loaded ${plugin##*/}$state in"
            echo "plug-elapsed '$start' '$end' '$message'"
        fi
    }
}

define-command -override -docstring \
"plug-install [<plugin>]: install <plugin>.
If <plugin> ommited installs all plugins mentioned in configuration files" \
plug-install -params ..1 %{
    nop %sh{ (
        plugin=$1
        if [ -d $(eval echo "$kak_opt_plug_install_dir/.plug.kaklock") ]; then
            printf %s\\n "evaluate-commands -client $kak_client echo -markup '{Information}.plug.kaklock is present. Waiting...'" | kak -p ${kak_session}
        fi
        while ! mkdir $(eval echo "$kak_opt_plug_install_dir/.plug.kaklock") 2>/dev/null; do sleep 1; done
        trap 'rmdir $(eval echo "$kak_opt_plug_install_dir/.plug.kaklock")' EXIT

        if [ ! -d $(eval echo $kak_opt_plug_install_dir) ]; then
            mkdir -p $(eval echo $kak_opt_plug_install_dir)
        fi

        if [ ! -z $plugin ]; then
            case $plugin in
                http*|git*)
                    git="git clone $plugin --depth 1" ;;
                *)
                    git="git clone $kak_opt_plug_git_domain/$plugin --depth 1" ;;
            esac
            if [ ! -d $(eval echo $kak_opt_plug_install_dir/"${plugin##*/}") ]; then
                printf %s\\n "evaluate-commands -client $kak_client echo -markup '{Information}Installing $plugin'" | kak -p ${kak_session}
                (
                    cd $(eval echo $kak_opt_plug_install_dir) && $git >/dev/null 2>&1
                    printf %s\\n "evaluate-commands -client $kak_client echo -debug 'installed ${plugin##*/}'" | kak -p ${kak_session}
                    printf %s\\n "evaluate-commands -client $kak_client plug $plugin" | kak -p ${kak_session}
                    exit
                ) &
            fi
        else
            jobs=$(mktemp ${TMPDIR:-/tmp}/jobs.XXXXXX)
            printf %s\\n "evaluate-commands -client $kak_client echo -markup '{Information}Installing plugins in background'" | kak -p ${kak_session}
            for plugin in $kak_opt_plug_plugins; do
                case $plugin in
                    http*|git*)
                        git="git clone $plugin --depth 1" ;;
                    *)
                        git="git clone $kak_opt_plug_git_domain/$plugin --depth 1" ;;
                esac
                if [ ! -d $(eval echo $kak_opt_plug_install_dir/"${plugin##*/}") ]; then
                    (
                        cd $(eval echo $kak_opt_plug_install_dir) && $git >/dev/null 2>&1
                        printf %s\\n "evaluate-commands -client $kak_client echo -debug 'installed ${plugin##*/}'" | kak -p ${kak_session}
                        printf %s\\n "evaluate-commands -client $kak_client plug-eval-hooks $plugin" | kak -p ${kak_session}
                        printf %s\\n "evaluate-commands -client $kak_client plug $plugin" | kak -p ${kak_session}
                    ) &
                fi
                jobs > $jobs; active=$(wc -l < $jobs)
                while [ $active -ge $kak_opt_plug_max_simultaneous_downloads ]; do
                    sleep 1
                    jobs > $jobs; active=$(wc -l < $jobs)
                done
            done
            wait
            rm -rf $jobs
        fi
        printf %s\\n "evaluate-commands -client $kak_client echo -markup '{Information}Done installing plugins'" | kak -p ${kak_session}
    ) >/dev/null 2>&1 < /dev/null & }
}

define-command -override -docstring \
"plug-update [<plugin>]: Update plugin.
If <plugin> ommited all installed plugins are updated" \
plug-update -params ..1 -shell-script-candidates %{ echo $kak_opt_plug_plugins | tr ' ' '\n' } %{
    evaluate-commands %sh{ (
        plugin=$1
        if [ -d $(eval echo "$kak_opt_plug_install_dir/.plug.kaklock") ]; then
            printf %s\\n "evaluate-commands -client $kak_client echo -markup '{Information}.plug.kaklock is present. Waiting...'" | kak -p ${kak_session}
        fi

        while ! mkdir $(eval echo "$kak_opt_plug_install_dir/.plug.kaklock") 2>/dev/null; do sleep 1; done
        trap 'rmdir $(eval echo "$kak_opt_plug_install_dir/.plug.kaklock")' EXIT
        if [ ! -z $plugin ]; then
            if [ -d $(eval echo $kak_opt_plug_install_dir/"${plugin##*/}") ]; then
                printf %s\\n "evaluate-commands -client $kak_client echo -markup '{Information}Updating $plugin'" | kak -p ${kak_session}
                (
                    cd $(eval echo $kak_opt_plug_install_dir/"${plugin##*/}") && rev=$(git rev-parse HEAD) && git pull -q
                    if [ $rev != $(git rev-parse HEAD) ]; then
                        printf %s\\n "evaluate-commands -client $kak_client plug-eval-hooks $plugin" | kak -p ${kak_session}
                    fi
                    printf %s\\n "evaluate-commands -client $kak_client echo -debug 'updated ${plugin##*/}'" | kak -p ${kak_session}
                ) &
            else
                printf %s\\n "evaluate-commands -client $kak_client echo -markup '{Error}can''t update $plugin. Plugin is not installed'" | kak -p ${kak_session}
                exit
            fi
        else
            printf %s\\n "evaluate-commands -client $kak_client echo -markup '{Information}Updating plugins in the background'" | kak -p ${kak_session}
            jobs=$(mktemp ${TMPDIR:-/tmp}/jobs.XXXXXX)
            for plugin in $kak_opt_plug_plugins; do
                (
                    cd $(eval echo $kak_opt_plug_install_dir/"${plugin##*/}") && rev=$(git rev-parse HEAD) && git pull -q
                    if [ $rev != $(git rev-parse HEAD) ]; then
                        printf %s\\n "evaluate-commands -client $kak_client plug-eval-hooks $plugin" | kak -p ${kak_session}
                    fi
                    printf %s\\n "evaluate-commands -client $kak_client echo -debug 'updated ${plugin##*/}'" | kak -p ${kak_session}
                ) &
                jobs > $jobs; active=$(wc -l < $jobs)
                while [ $active -ge $kak_opt_plug_max_simultaneous_downloads ]; do
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

define-command -override -docstring \
"plug-delete [<plugin>]: delete <plugin>.
If <plugin> ommited deletes all plugins that are not presented in configuration files" \
plug-clean -params ..1 -shell-script-candidates %{ ls -1 $(eval echo $kak_opt_plug_install_dir) } %{
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
                printf %s\\n "evaluate-commands -client $kak_client echo -debug 'removed ${plugin##*/}'" | kak -p ${kak_session}
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
                printf %s\\n "evaluate-commands -client $kak_client echo -debug 'removed ${plugin##*/}'" | kak -p ${kak_session}
            done
        fi
    ) > /dev/null 2>&1 < /dev/null & }
}

define-command -override -hidden \
-docstring "plug-configure: wrapper for configuring plugin" \
plug-configure -params 1 %{ evaluate-commands %sh{
    plugin=$(echo "${1##*/}" | sed 's:[^a-zA-Z0-9_]:_:g;')
    IFS='┆'
    for configuration in $kak_opt_plug_configurations; do
        if [ "${configuration%%:*}" = "$plugin" ]; then
            IFS='
'
            for cmd in "${configuration#*:}"; do
                echo "$cmd"
            done
            break
        fi
    done
}}

define-command -override -hidden \
-docstring "plug-eval-hooks: wrapper for post update/install hooks" \
plug-eval-hooks -params 1 %{
    nop %sh{ (
        plugin=$(echo "${1##*/}" | sed 's:[^a-zA-Z0-9_]:_:g;')
        IFS='┆'
        for hook in $kak_opt_plug_post_hooks; do
            if [ "${hook%%:*}" = "$plugin" ]; then
                temp=$(mktemp ${TMPDIR:-/tmp}/$plugin.XXXXXX)
                printf %s\\n "evaluate-commands -client $kak_client echo -debug %{running post-update hooks for ${1##*/}}" | kak -p ${kak_session}
                cd $(eval echo "$kak_opt_plug_install_dir/${1##*/}")
                IFS='
'
                for cmd in "${hook#*:}"; do
                    eval "$cmd" >$temp 2>&1
                    if [ $? -eq 1 ]; then
                        error=1
                        log=$(cat $temp)
                        break
                    fi
                done
                if [ -z $error ]; then
                    printf %s\\n "evaluate-commands -client $kak_client echo -debug %{finished post-update hooks for ${1##*/}}" | kak -p ${kak_session}
                else
                    printf %s\\n "evaluate-commands -client $kak_client echo -debug %{error occured while evaluation of post-update hooks for ${1##*/}:}" | kak -p ${kak_session}
                    printf %s\\n "evaluate-commands -client $kak_client echo -debug %{$log}" | kak -p ${kak_session}
                fi
                rm -rf $temp
                break
            fi
        done
    ) > /dev/null 2>&1 < /dev/null & }
}

define-command -override -hidden \
-docstring "plug-elapsed <start> <end> <msg> prints elapsed time" \
plug-elapsed -params 3 %{
    evaluate-commands %sh{
        if [ "$kak_opt_plug_profiler" = "true" ]; then
            start=$1; shift;
            end=$1; shift;
            message=$1;
            if [ $start -gt $end ]; then
                echo "echo -debug %{Error: 'start: $start' time is bigger than 'end: $end' time}"
                exit
            fi
            load_time=$(echo "in $(expr $end - $start)" | sed -e "s:\(.*\)\(..$\):\1.\2:;s:in \.:in 0.:;s:in\. \(.\):in 0.0\1:;s:in ::")
            echo "echo -debug %{$message $load_time seconds}"
        fi
    }
}
