# ╭─────────────╥──────────╥─────────────╮
# │ Author:     ║ File:    ║ Branch:     │
# │ Andrey Orst ║ plug.kak ║ kakoune-git │
# ╞═════════════╩══════════╩═════════════╡
# │ plug.kak is a plugin manager for     │
# │ Kakoune. It can install plugins      │
# │ keep them updated and uninstall      │
# ╞══════════════════════════════════════╡
# │ GitHub repo:                         │
# │ GitHub.com/andreyorst/plug.kak       │
# ╰──────────────────────────────────────╯

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
str-list plug_post_hooks ''

declare-option -hidden -docstring \
"List of configurations for all mentioned plugins" \
str-list plug_configurations ''

declare-option -hidden -docstring \
"List of filest to load for all mentioned plugins" \
str-list plug_load_files ''

declare-option -docstring \
"always ensure sthat all plugins are installed" \
bool plug_always_ensure false

hook global WinSetOption filetype=kak %{ try %{
    add-highlighter window/plug_keywords   regex \b(plug|do|config|load)\b\h+((?=")|(?=')|(?=%)|(?=\w)) 0:keyword
    add-highlighter window/plug_attributes regex \b(noload|ensure)\b 0:attribute
    hook  global WinSetOption filetype=(?!kak).* %{ try %{
        remove-highlighter window/plug_keywords
        remove-highlighter window/plug_attributes
    }}
}}

# Highlighters
add-highlighter shared/plug group
add-highlighter shared/plug/done          regex ^([^:]+)(:)\h+(Up\h+to\h+date|Done)$           1:Default 2:keyword 3:string
add-highlighter shared/plug/update        regex ^([^:]+)(:)\h+(Update\h+available)$            1:Default 2:keyword 3:type
add-highlighter shared/plug/not_installed regex ^([^:]+)(:)\h+(Not\h+installed)$               1:Default 2:keyword 3:Error
add-highlighter shared/plug/updating      regex ^([^:]+)(:)\h+(Installing|Updating)$           1:Default 2:keyword 3:type
add-highlighter shared/plug/working       regex ^([^:]+)(:)\h+(Running\h+post-update\h+hooks)$ 1:Default 2:keyword 3:attribute

hook -group plug-syntax global WinSetOption filetype=plug %{
  add-highlighter window/plug ref plug
  hook -always -once window WinSetOption filetype=.* %{
    remove-highlighter window/plug
  }
}

define-command -override -docstring \
"plug <plugin> [<branch>|<tag>|<commit>] [<noload>|<load> <subset>] [[<config>] <configurations>]: load <plugin> from ""%opt{plug_install_dir}""
" \
plug -params 1.. -shell-script-candidates %{ ls -1 $kak_opt_plug_install_dir } %{
    evaluate-commands %sh{
        plugin=$1; shift
        plugin_name="${plugin##*/}"
        noload=
        load=
        ensure=
        state=
        loaded=$kak_opt_plug_loaded_plugins

        if [ $(expr "${kak_opt_plug_plugins}" : ".*$plugin.*") -eq 0 ]; then
            printf "%s\n" "set-option -add global plug_plugins \"%arg{1} \""
        fi

        if [ -n "$loaded" ] && [ -z "${loaded##*$plugin*}" ]; then
            echo "echo -markup %{{Information}${plugin_name} already loaded}"
            exit
        fi

        for arg in $@; do
            case $arg in
                *branch:*|*tag:*|*commit:*)
                    branch=$(echo $1 | awk '{print $2}')
                    shift ;;
                noload)
                    noload=1
                    shift ;;
                load)
                    shift;
                    echo "set-option -add global plug_load_files %{$plugin_name:$1}"
                    load=1
                    shift ;;
                do)
                    shift;
                    echo "set-option -add global plug_post_hooks %{$plugin_name:$1}"
                    shift ;;
                ensure)
                    ensure=1
                    shift ;;
                config)
                    shift
                    echo "set-option -add global plug_configurations %{$plugin_name:$1}"
                    shift ;;
                *)
                    ;;
            esac
        done

        if [ -n "$noload" ] && [ -n "$load" ]; then
            echo "echo -debug %{plug.kak: warning, using both 'load' and 'noload' for ${plugin##*/} plugin}"
            echo "echo -debug %{          'load' has higer priority so 'noload' will be ignored.}"
            noload=
        fi

        if [ -z "$load" ]; then
            echo "set-option -add global plug_load_files %{$plugin_name:*.kak}"
        fi

        if [ $# -gt 0 ]; then
            echo "set-option -add global plug_configurations %{$plugin_name:$1}"
        fi

        if [ -d $kak_opt_plug_install_dir ]; then
            if [ -d "$kak_opt_plug_install_dir/${plugin##*/}" ]; then
                if [ -n "$branch" ]; then
                    (cd "$kak_opt_plug_install_dir/${plugin##*/}"; git checkout $branch >/dev/null 2>&1)
                fi
                if [ -z "$noload" ]; then
                    echo "plug-load $plugin"
                fi
                plug_conf=$(echo "${plugin##*/}" | sed 's:[^a-zA-Z0-9_]:_:g;')
                if [ -z "${kak_opt_configurations##*$plug_conf*}" ]; then
                    echo "plug-configure $plugin"
                fi
                echo "set-option -add global plug_loaded_plugins %{$plugin }"
            else
                if [ -n "$ensure" ] || [ "$kak_opt_plug_always_ensure" = "true" ]; then
                    echo "evaluate-commands -client ${kak_client:-client0} plug-install $plugin" | kak -p ${kak_session}
                else
                    exit
                fi
            fi
        fi
    }
}

define-command -override -docstring \
"plug-install [<plugin>]: install <plugin>.
If <plugin> ommited installs all plugins mentioned in configuration files" \
plug-install -params ..1 %{
    nop %sh{ (
        plugin=$1
        jobs=$(mktemp ${TMPDIR:-/tmp}/jobs.XXXXXX)

        printf "%s\n" "evaluate-commands -client $kak_client plug-list" | kak -p ${kak_session}
        sleep 0.2

        if [ -d "$kak_opt_plug_install_dir/.plug.kaklock" ]; then
            printf "%s\n" "evaluate-commands -client $kak_client echo -markup '{Information}.plug.kaklock is present. Waiting...'" | kak -p ${kak_session}
        fi

        while ! mkdir "$kak_opt_plug_install_dir/.plug.kaklock" 2>/dev/null; do sleep 1; done
        trap 'rmdir "$kak_opt_plug_install_dir/.plug.kaklock"' EXIT

        if [ ! -d $kak_opt_plug_install_dir ]; then
            mkdir -p $kak_opt_plug_install_dir
        fi

        if [ -n "$plugin" ]; then
            plugin_list=$plugin
            printf "%s\n" "evaluate-commands -client $kak_client echo -markup '{Information}Installing $plugin'" | kak -p ${kak_session}
        else
            plugin_list=$kak_opt_plug_plugins
            printf "%s\n" "evaluate-commands -client $kak_client echo -markup '{Information}Installing plugins in background'" | kak -p ${kak_session}
        fi

        for plugin in $plugin_list; do
            case $plugin in
                http*|git*)
                    git="git clone $plugin" ;;
                *)
                    git="git clone $kak_opt_plug_git_domain/$plugin" ;;
            esac
            if [ ! -d "$kak_opt_plug_install_dir/${plugin##*/}" ]; then
                (
                    printf "%s\n" "evaluate-commands -client $kak_client %{ plug-update-fifo %{${plugin}} %{Installing} }" | kak -p ${kak_session}
                    cd $kak_opt_plug_install_dir && $git >/dev/null 2>&1
                    wait
                    printf "%s\n" "evaluate-commands -client $kak_client plug-eval-hooks $plugin" | kak -p ${kak_session}
                    printf "%s\n" "evaluate-commands -client $kak_client plug $plugin" | kak -p ${kak_session}
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
    ) >/dev/null 2>&1 < /dev/null & }
}

define-command -override -docstring \
"plug-update [<plugin>]: Update plugin.
If <plugin> ommited all installed plugins are updated" \
plug-update -params ..1 -shell-script-candidates %{ echo $kak_opt_plug_plugins | tr ' ' '\n' } %{
    evaluate-commands %sh{ (
        plugin=$1
        jobs=$(mktemp ${TMPDIR:-/tmp}/jobs.XXXXXX)

        printf "%s\n" "evaluate-commands -client $kak_client plug-list" | kak -p ${kak_session}
        sleep 0.2

        if [ -d "$kak_opt_plug_install_dir/.plug.kaklock" ]; then
            printf "%s\n" "evaluate-commands -client $kak_client echo -markup '{Information}.plug.kaklock is present. Waiting...'" | kak -p ${kak_session}
        fi

        while ! mkdir "$kak_opt_plug_install_dir/.plug.kaklock" 2>/dev/null; do sleep 1; done
        trap 'rmdir "$kak_opt_plug_install_dir/.plug.kaklock"' EXIT

        if [ -n "$plugin" ]; then
            plugin_list=$plugin
        else
            plugin_list=$kak_opt_plug_plugins
        fi
        for plugin in $plugin_list; do
            (
                printf "%s\n" "evaluate-commands -client $kak_client %{ plug-update-fifo %{${plugin}} %{Updating} }" | kak -p ${kak_session}
                cd "$kak_opt_plug_install_dir/${plugin##*/}" && rev=$(git rev-parse HEAD) && git pull -q
                if [ $rev != $(git rev-parse HEAD) ]; then
                    printf "%s\n" "evaluate-commands -client $kak_client plug-eval-hooks $plugin" | kak -p ${kak_session}
                fi
            ) &
            jobs > $jobs; active=$(wc -l < $jobs)
            while [ $active -ge $kak_opt_plug_max_simultaneous_downloads ]; do
                sleep 1
                jobs > $jobs; active=$(wc -l < $jobs)
            done
        done
        rm -rf $jobs
        wait
    ) > /dev/null 2>&1 < /dev/null & }
}

define-command -override -docstring \
"plug-delete [<plugin>]: delete <plugin>.
If <plugin> ommited deletes all plugins that are not presented in configuration files" \
plug-clean -params ..1 -shell-script-candidates %{ ls -1 $kak_opt_plug_install_dir } %{
    nop %sh{ (
        plugin=$1

        if [ -d "$kak_opt_plug_install_dir/.plug.kaklock" ]; then
            printf "%s\n" "evaluate-commands -client $kak_client echo -markup '{Information}.plug.kaklock is present. Waiting...'" | kak -p ${kak_session}
        fi

        while ! mkdir "$kak_opt_plug_install_dir/.plug.kaklock" 2>/dev/null; do sleep 1; done
        trap 'rmdir "$kak_opt_plug_install_dir/.plug.kaklock"' EXIT

        if [ -n "$plugin" ]; then
            if [ -d "$kak_opt_plug_install_dir/${plugin##*/}" ]; then
                (cd $kak_opt_plug_install_dir && rm -rf "${plugin##*/}")
            else
                printf "%s\n" "evaluate-commands -client $kak_client echo -markup %{{Error}No such plugin '$plugin'}" | kak -p ${kak_session}
                exit
            fi
        else
            for installed_plugin in $(echo $kak_opt_plug_install_dir/*); do
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

define-command -override -hidden \
-docstring "plug-configure: wrapper for configuring plugin" \
plug-configure -params 1 %{ evaluate-commands %sh{
    plugin="${1##*/}"
    eval "set -- $kak_opt_plug_configurations"
    while [ $# -gt 0 ]; do
        if [ "${1%%:*}" = "$plugin" ]; then
            IFS='
'
            for cmd in ${1#*:}; do
                echo "$cmd"
            done
            break
        fi
        shift
    done
}}

define-command -override -hidden \
-docstring "plug-load: load selected subset of files from repository" \
plug-load -params 1 %{ evaluate-commands %sh{
    plugin="${1##*/}"
    eval "set -- $kak_opt_plug_load_files"
    while [ $# -gt 0 ]; do
        if [ "${1%%:*}" = "$plugin" ]; then
            IFS='
'
            set -f # set noglob
            for file in ${1#*:}; do
                file="${file#"${file%%[![:space:]]*}"}"
                file="${file%"${file##*[![:space:]]}"}"
                for script in $(find -L $kak_opt_plug_install_dir/$plugin -type f -name "$file" | awk -F/ '{print NF-1, $0}' | sort -n | cut -d' ' -f2); do
                    echo source "$script"
                done
            done
            break
        fi
        shift
    done
}}

define-command -override -hidden \
-docstring "plug-eval-hooks: wrapper for post update/install hooks" \
plug-eval-hooks -params 1 %{
    nop %sh{ (
        plugin=$1
        plugin_name="${plugin##*/}"
        eval "set -- $kak_opt_plug_post_hooks"
        while [ $# -gt 0 ]; do
            if [ "${1%%:*}" = "$plugin_name" ]; then
                temp=$(mktemp ${TMPDIR:-/tmp}/$plugin_name-log.XXXXXX)
                cd "$kak_opt_plug_install_dir/$plugin_name"
                printf "%s\n" "evaluate-commands -client $kak_client %{ plug-update-fifo %{${plugin}} %{Running post-update hooks} }" | kak -p ${kak_session}
                IFS=';
'
                for cmd in ${1#*:}; do
                    eval "$cmd" >$temp 2>&1
                    status=$?
                    if [ ! $status -eq 0 ]; then
                        break
                    fi
                done

                if [ $status -eq 0 ]; then
                    rm -rf $temp
                else
                    printf "%s\n" "evaluate-commands -client $kak_client %{ plug-update-fifo %{${plugin}} %{Error} }" | kak -p ${kak_session}
                    printf "%s\n%s\n%s\n" "evaluate-commands -client $kak_client echo -debug %{error occured while evaluation of post-update hooks for $plugin_name:}" \
                    "evaluate-commands -client $kak_client echo -debug %sh{cat $temp; rm -rf $temp}" \
                    "evaluate-commands -client $kak_client echo -debug %{aborting hooks for $plugin_name with code: $status}" | kak -p ${kak_session}
                fi
                break
            fi
            shift
        done
        printf "%s\n" "evaluate-commands -client $kak_client %{ plug-update-fifo %{${plugin}} %{Done} }" | kak -p ${kak_session}
    ) > /dev/null 2>&1 < /dev/null & }
}

define-command -override \
-docstring "plug-list: list all installed plugins in *plug* buffer" \
plug-list %{ evaluate-commands %sh{
    fifo=$(mktemp -d "${TMPDIR:-/tmp}"/plug-kak.XXXXXXXX)/fifo
    mkfifo ${fifo}

    (   eval "set -- $kak_opt_plug_plugins"
        while [ $# -gt 0 ]; do
            if [ -d "$kak_opt_plug_install_dir/${1##*/}" ]; then
                (
                    cd $kak_opt_plug_install_dir/${1##*/}
                    if git diff --quiet remotes/origin/HEAD; then
                        printf "%s: %s\n" $1 "Up to date" >> ${fifo}
                    else
                        printf "%s: %s\n" $1 "Update available" >> ${fifo}
                    fi
                )
            else
                printf "%s: %s\n" $1 "Not installed" >> ${fifo}
            fi
            shift
        done
    ) > /dev/null 2>&1 < /dev/null &

    printf "%s\n" "try %{ delete-buffer *plug* }
                   edit! -fifo ${fifo} *plug*
                   set-option window filetype plug
                   hook -always -once buffer BufCloseFifo .* %{ nop %sh{ rm -r ${fifo%/*} } }
                   map buffer normal '<ret>' ':<space>plug-fifo-operate<ret>'"
}}

define-command -override \
-docstring "operate on *plug* buffer contents based on current cursor position" \
plug-fifo-operate %{ evaluate-commands -save-regs t %{
    execute-keys -save-regs '' "<a-h><a-l>"
    set-register t %val{selection}
    evaluate-commands %sh{
        plugin="${kak_reg_t%:*}"
        if [ -d "$kak_opt_plug_install_dir/${plugin##*/}" ]; then
            printf "%s\n" "plug-update $plugin'"
        else
            printf "%s\n" "plug-install $plugin'"
        fi
    }
}}

define-command -override \
-docstring "plug-update-fifo <plugin> <message>" \
plug-update-fifo -params 2 %{ evaluate-commands -buffer *plug* -save-regs "/""" %{
    set-register / "%arg{1}: "
    set-register dquote %arg{2}
    execute-keys /<ret>lGlR
}}
