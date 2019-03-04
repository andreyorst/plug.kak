# ╭─────────────╥──────────╥─────────────╮
# │ Author:     ║ File:    ║ Branch:     │
# │ Andrey Orst ║ plug.kak ║ v2019.01.20 │
# ╞═════════════╩══════════╩═════════════╡
# │ plug.kak is a plugin manager for     │
# │ Kakoune. It can install plugins      │
# │ keep them updated and uninstall      │
# ╞══════════════════════════════════════╡
# │ GitHub repo:                         │
# │ GitHub.com/andreyorst/plug.kak       │
# ╰──────────────────────────────────────╯

# Public options
declare-option -docstring \
"path where plugins should be installed.

    Default value: '%val{config}/plugins'" \
str plug_install_dir "%val{config}/plugins"

declare-option -docstring \
"default domain to access git repositories. Can be changed to any preferred domain, like gitlab, bitbucket, gitea, etc.

    Default value: 'https://github.com'" \
str plug_git_domain 'https://github.com'

declare-option -docstring \
"Maximum amount of simultaneously active downloads when installing or updating all plugins
    Default value: 10
" \
int plug_max_active_downloads 10

declare-option -docstring \
"always ensure that all plugins are installed. If this option specified, all uninstalled plugins are being installed when Kakoune starts." \
bool plug_always_ensure false

declare-option -docstring "name of the client in which utilities display information" \
str toolsclient

# Private options
declare-option -hidden -docstring \
"Array of all plugins, mentioned in any configuration file.
Empty by default, and erased on reload of main Kakoune configuration, to track if some plugins were disabled
Should not be modified by user." \
str plug_plugins ''

declare-option -hidden -docstring \
"List of loaded plugins. Has no default value.
Should not be cleared during update of configuration files. Should not be modified by user." \
str plug_loaded_plugins

declare-option -hidden -docstring \
"List of post update/install hooks to be executed" \
str-list plug_post_hooks ''

# kakrc highlighters
add-highlighter shared/kakrc/code/plug_keywords   regex \b(plug|do|config|load)\b\h+((?=")|(?=')|(?=%)|(?=\w)) 0:keyword
add-highlighter shared/kakrc/code/plug_attributes regex \b(noload|ensure|branch|tag|commit|theme)\b 0:attribute
add-highlighter shared/kakrc/plug_post_hooks      region -recurse '\{' '\bdo\h+%\{' '\}' ref sh

# *plug* highlighters
add-highlighter shared/plug_buffer group
add-highlighter shared/plug_buffer/done          regex [^:]+:\h+(Up\h+to\h+date|Done|Installed)$                    1:string
add-highlighter shared/plug_buffer/update        regex [^:]+:\h+(Update\h+available|Deleted)$                       1:keyword
add-highlighter shared/plug_buffer/not_installed regex [^:]+:\h+(Not\h+(installed|loaded)|(\w+\h+)?Error([^\n]+)?)$ 1:Error
add-highlighter shared/plug_buffer/updating      regex [^:]+:\h+(Installing|Updating|Local\h+changes)$              1:type
add-highlighter shared/plug_buffer/working       regex [^:]+:\h+(Running\h+post-update\h+hooks|Waiting[^\n]+)$                    1:attribute

hook -group plug-syntax global WinSetOption filetype=plug %{
    add-highlighter window/plug_buffer ref plug_buffer
    hook -always -once window WinSetOption filetype=.* %{
        remove-highlighter window/plug_buffer
    }
}

define-command -override -docstring \
"plug <plugin> [<branch>|<tag>|<commit>] [<noload>|<load> <subset>] [[<config>] <configurations>]: load <plugin> from ""%opt{plug_install_dir}""" \
plug -params 1.. -shell-script-candidates %{ ls -1 ${kak_opt_plug_install_dir} } %{ try %{
    evaluate-commands %sh{
        plugin="${1%%.git}"
        shift
        plugin_name="${plugin##*/}"
        plugin_opt_name=$(printf "%s\n" "${plugin_name}" | sed 's/[^a-zA-Z0-9_]/_/g')
        load_files='*.kak'

        if [ $(expr "${kak_opt_plug_loaded_plugins}" : ".*${plugin}.*") -ne 0 ]; then
            printf "%s\n" "echo -markup %{{Information}${plugin_name} already loaded}"
            exit
        fi

        if [ $(expr "${kak_opt_plug_plugins}" : ".*${plugin}.*") -eq 0 ]; then
            printf "%s\n" "set-option -add global plug_plugins %{${plugin} }"
        fi

        while [ $# -gt 0 ]; do
            case $1 in
                branch|tag|commit)
                    branch_type=$1
                    shift
                    checkout="$1" ;;
                noload)
                    noload=1 ;;
                load)
                    shift
                    load=1
                    load_files="$1" ;;
                do)
                    shift
                    hooks="${hooks} %{${plugin_name}} %{$1}" ;;
                ensure)
                    ensure=1 ;;
                theme)
                    noload=1
                    theme_hooks="mkdir -p ${kak_config}/colors
                           find -type f -name '*.kak' -exec cp {} ${kak_config}/colors/ \;"
                    hooks="${hooks} %{${plugin_name}} %{${theme_hooks}}" ;;
                config)
                    shift
                    configurations="${configurations} $1" ;;
                *)
                    configurations="${configurations} $1" ;;
            esac
            shift
        done

        # bake configuration options. We need this in case plugins are not installed, but
        # their configurations are known to `plug.kak', so it can load those after installation
        # automatically.
        if [ -n "${configurations}" ]; then
            printf "%s\n" "declare-option -hidden str plug_${plugin_opt_name}_conf %{${configurations}}"
        else
            printf "%s\n" "declare-option -hidden str plug_${plugin_opt_name}_conf"
        fi

        if [ -n "${hooks}" ]; then
            printf "%s\n" "set-option -add global plug_post_hooks ${hooks}"
        fi

        if [ -n "${noload}" ] && [ -n "${load}" ]; then
            printf "%s\n" "echo -debug %{Warning: plug.kak: ${plugin_name}: 'load' has higer priority than 'noload'}"
            noload=
        fi

        if [ -d "${kak_opt_plug_install_dir}/${plugin##*/}" ]; then
            if [ -n "${checkout}" ]; then
                (
                    cd "${kak_opt_plug_install_dir}/${plugin##*/}"
                    [ -z "${GIT_TERMINAL_PROMPT}" ] && export GIT_TERMINAL_PROMPT=0
                    if [ "${branch_type}" = "branch" ]; then
                        current_branch=$(git branch | awk '/^\*/ { print $2 }')
                        [ "${current_branch}" != "${checkout}" ] && git fetch >/dev/null 2>&1
                    fi
                    git checkout ${checkout} >/dev/null 2>&1
                )
            fi
            if [ -z "${noload}" ]; then {
                IFS='
'
                set -f # set noglob
                for file in "${load_files}"; do
                    # trim leading and trailing whitespaces. faster than `sed'
                    file="${file#"${file%%[![:space:]]*}"}"
                    file="${file%"${file##*[![:space:]]}"}"
                    # performance hungry place. We need to sort find's output by depth.
                    find -L ${kak_opt_plug_install_dir}/${plugin_name} -path '*/.git' -prune -o -type f -name "${file}" -print | perl -e '
                        @sorted = map  { $_->[0] }
                                  sort { $a->[1] <=> $b->[1] }
                                  map  { [$_, ($_ =~ s/\//\//g)] }
                                       <>;
                        chomp(@sorted);
                        print "source \"", $_, "\"\n" for @sorted;'
                done
            } fi
            printf "%s\n" "evaluate-commands \"%opt{plug_${plugin_opt_name}_conf}\""
            printf "%s\n" "set-option -add global plug_loaded_plugins %{${plugin} }"
        else
            if [ -n "${ensure}" ] || [ "${kak_opt_plug_always_ensure}" = "true" ]; then
                printf "%s\n" "evaluate-commands plug-install ${plugin}"
            fi
        fi
    }
} catch %{
    echo -debug "Error occured while loading %arg{1} plugin"
}}

define-command -override -docstring \
"plug-install [<plugin>]: install <plugin>.
If <plugin> omitted installs all plugins mentioned in configuration files" \
plug-install -params ..1 %{
    nop %sh{ (
        plugin=$1
        jobs=$(mktemp ${TMPDIR:-/tmp}/plug.kak.jobs.XXXXXX)

        [ -z "${GIT_TERMINAL_PROMPT}" ] && export GIT_TERMINAL_PROMPT=0

        if [ ! -d ${kak_opt_plug_install_dir} ]; then
            if ! mkdir -p ${kak_opt_plug_install_dir} >/dev/null 2>&1; then
                printf "%s\n" "evaluate-commands -client ${kak_client} echo -debug 'plug.kak Error: unable to create directory to host plugins'" | kak -p ${kak_session}
                exit
            fi
        fi

        printf "%s\n" "evaluate-commands -client ${kak_client} %{ try %{ buffer *plug* } catch %{ plug-list noupdate } }" | kak -p ${kak_session}

        if [ -d "${kak_opt_plug_install_dir}/.plug.kak.lock" ]; then
            lock=1
            printf "%s\n" "evaluate-commands -client ${kak_client} %{ plug-update-fifo %{${plugin##*/}} %{Waiting for .plug.kak.lock} }" | kak -p ${kak_session}
        fi

        while ! mkdir "${kak_opt_plug_install_dir}/.plug.kak.lock" 2>/dev/null; do sleep 1; done
        trap 'rmdir "${kak_opt_plug_install_dir}/.plug.kak.lock"' EXIT

        if [ -n "${plugin}" ]; then
            plugin_list=${plugin}
            printf "%s\n" "evaluate-commands -buffer *plug* %{
                try %{
                    execute-keys /${plugin}<ret>
                } catch %{
                    execute-keys gjO${plugin}:<space>Not<space>installed<esc>
                }
            }" | kak -p ${kak_session}
            sleep 0.2
        else
            plugin_list=${kak_opt_plug_plugins}
        fi

        for plugin in ${plugin_list}; do
            plugin_name="${plugin##*/}"
            if [ ! -d "${kak_opt_plug_install_dir}/${plugin##*/}" ]; then
                case ${plugin} in
                    http*|git*)
                        git="git clone ${plugin}" ;;
                    *)
                        git="git clone ${kak_opt_plug_git_domain}/${plugin}" ;;
                esac

                (
                    printf "%s\n" "evaluate-commands -client ${kak_client} %{ plug-update-fifo %{${plugin_name}} %{Installing} }" | kak -p ${kak_session}
                    cd ${kak_opt_plug_install_dir} && ${git} >/dev/null 2>&1
                    status=$?
                    if [ ${status} -ne 0 ]; then
                        printf "%s\n" "evaluate-commands -client ${kak_client} %{ plug-update-fifo %{${plugin_name}} %{Download Error (${status})} }" | kak -p ${kak_session}
                    else
                        printf "%s\n" "evaluate-commands -client ${kak_client} plug-eval-hooks ${plugin_name}" | kak -p ${kak_session}
                        printf "%s\n" "evaluate-commands -client ${kak_client} plug ${plugin}" | kak -p ${kak_session}
                    fi
                ) > /dev/null 2>&1 < /dev/null &
            fi
            jobs > ${jobs}; active=$(wc -l < ${jobs})
            while [ ${active} -ge ${kak_opt_plug_max_active_downloads} ]; do
                sleep 1
                jobs > ${jobs}; active=$(wc -l < ${jobs})
            done
        done
        wait
        rm -rf ${jobs}
    ) >/dev/null 2>&1 < /dev/null & }
}

define-command -override -docstring \
"plug-update [<plugin>]: Update plugin.
If <plugin> omitted all installed plugins are updated" \
plug-update -params ..1 -shell-script-candidates %{ printf "%s\n" ${kak_opt_plug_plugins} | tr ' ' '\n' } %{
    evaluate-commands %sh{ (
        plugin=$1
        jobs=$(mktemp ${TMPDIR:-/tmp}/jobs.XXXXXX)

        [ -z "${GIT_TERMINAL_PROMPT}" ] && export GIT_TERMINAL_PROMPT=0

        printf "%s\n" "evaluate-commands -client ${kak_client} %{ try %{ buffer *plug* } catch %{ plug-list noupdate } }" | kak -p ${kak_session}

        if [ -d "${kak_opt_plug_install_dir}/.plug.kak.lock" ]; then
            lock=1
            printf "%s\n" "evaluate-commands -client ${kak_client} %{ plug-update-fifo %{${plugin##*/}} %{Waiting for .plug.kak.lock} }" | kak -p ${kak_session}
        fi

        while ! mkdir "${kak_opt_plug_install_dir}/.plug.kak.lock" 2>/dev/null; do sleep 1; done
        trap 'rmdir "${kak_opt_plug_install_dir}/.plug.kak.lock"' EXIT

        [ -n "${plugin}" ] && plugin_list=${plugin} || plugin_list=${kak_opt_plug_plugins}
        for plugin in ${plugin_list}; do
            plugin_name="${plugin##*/}"
            if [ -d "${kak_opt_plug_install_dir}/${plugin_name}" ]; then
                (
                    printf "%s\n" "evaluate-commands -client ${kak_client} %{ plug-update-fifo %{${plugin_name}} %{Updating} }" | kak -p ${kak_session}
                    cd "${kak_opt_plug_install_dir}/${plugin_name}" && rev=$(git rev-parse HEAD) && git pull -q
                    status=$?
                    if [ ${status} -ne 0 ]; then
                        printf "%s\n" "evaluate-commands -client ${kak_client} %{ plug-update-fifo %{${plugin_name}} %{Update Error (${status})} }" | kak -p ${kak_session}
                    else
                        if [ ${rev} != $(git rev-parse HEAD) ]; then
                            printf "%s\n" "evaluate-commands -client ${kak_client} plug-eval-hooks ${plugin_name}" | kak -p ${kak_session}
                        else
                            printf "%s\n" "evaluate-commands -client ${kak_client} %{ plug-update-fifo %{${plugin_name}} %{Done} }" | kak -p ${kak_session}
                        fi
                    fi
                ) > /dev/null 2>&1 < /dev/null &
            fi
            jobs > ${jobs}; active=$(wc -l < ${jobs})
            while [ ${active} -ge $(expr ${kak_opt_plug_max_active_downloads} \* 5) ]; do
                sleep 1
                jobs > ${jobs}; active=$(wc -l < ${jobs})
            done
        done
        rm -rf ${jobs}
        wait
    ) > /dev/null 2>&1 < /dev/null & }
}

define-command -override -docstring \
"plug-clean [<plugin>]: delete <plugin>.
If <plugin> omitted deletes all plugins that are installed but not presented in configuration files" \
plug-clean -params ..1 -shell-script-candidates %{ ls -1 ${kak_opt_plug_install_dir} } %{
    nop %sh{ (
        plugin=$1
        plugin_name="${plugin##*/}"

        printf "%s\n" "evaluate-commands -client ${kak_client} %{ try %{ buffer *plug* } catch %{ plug-list noupdate } }" | kak -p ${kak_session}

        if [ -d "${kak_opt_plug_install_dir}/.plug.kak.lock" ]; then
            printf "%s\n" "evaluate-commands -client ${kak_client} echo -markup '{Information}.plug.kak.lock is present. Waiting...'" | kak -p ${kak_session}
        fi

        while ! mkdir "${kak_opt_plug_install_dir}/.plug.kak.lock" 2>/dev/null; do sleep 1; done
        trap 'rmdir "${kak_opt_plug_install_dir}/.plug.kak.lock"' EXIT

        if [ -n "${plugin}" ]; then
            if [ -d "${kak_opt_plug_install_dir}/${plugin_name}" ]; then
                printf "%s\n" "evaluate-commands -client ${kak_client} %{ plug-update-fifo %{${plugin_name}} %{Deleted} }" | kak -p ${kak_session}
                (cd ${kak_opt_plug_install_dir} && rm -rf "${plugin_name}")
            else
                printf "%s\n" "evaluate-commands -client ${kak_client} echo -markup %{{Error}No such plugin '${plugin}'}" | kak -p ${kak_session}
                exit
            fi
        else
            for installed_plugin in $(printf "%s\n" ${kak_opt_plug_install_dir}/*); do
                skip=
                for enabled_plugin in ${kak_opt_plug_plugins}; do
                    [ "${installed_plugin##*/}" = "${enabled_plugin##*/}" ] && { skip=1; break; }
                done
                [ "${skip}" = "1" ] || plugins_to_remove=${plugins_to_remove}" ${installed_plugin}"
            done
            for plugin in ${plugins_to_remove}; do
                printf "%s\n" "evaluate-commands -client ${kak_client} %{ plug-update-fifo %{${plugin##*/}} %{Deleted} }" | kak -p ${kak_session}
                rm -rf ${plugin}
            done
        fi
    ) > /dev/null 2>&1 < /dev/null & }
}

define-command -override -hidden \
-docstring "plug-eval-hooks: wrapper for post update/install hooks" \
plug-eval-hooks -params 1 %{
    nop %sh{ (
        status=0
        plugin_name="$1"
        eval "set -- ${kak_opt_plug_post_hooks}"
        while [ $# -gt 0 ]; do
            if [ "$1" = "${plugin_name}" ]; then
                temp=$(mktemp ${TMPDIR:-/tmp}/${plugin_name}-log.XXXXXX)
                cd "${kak_opt_plug_install_dir}/${plugin_name}"
                printf "%s\n" "evaluate-commands -client ${kak_client} %{ plug-update-fifo %{${plugin_name}} %{Running post-update hooks} }" | kak -p ${kak_session}
                IFS='
'
                for cmd in $2; do
                    eval "${cmd}" > ${temp} 2>&1
                    status=$?
                    if [ ! ${status} -eq 0 ]; then
                        break
                    fi
                done

                if [ ${status} -eq 0 ]; then
                    rm -rf ${temp}
                else
                    printf "%s\n%s\n%s\n" "evaluate-commands -client ${kak_client} %{ echo -debug %{plug.kak: error occured while evaluation of post-update hooks for ${plugin_name}:} }" \
                    "evaluate-commands -client ${kak_client} %{ echo -debug %sh{cat ${temp}; rm -rf ${temp}} }" \
                    "evaluate-commands -client ${kak_client} %{ echo -debug %{aborting hooks for ${plugin_name} with code ${status}} }" | kak -p ${kak_session}
                fi
                break
            fi
            shift
        done
        if [ ${status} -ne 0 ]; then
            message="Error (${status})"
        else
            message="Done"
        fi
        printf "%s\n" "evaluate-commands -client ${kak_client} %{ plug-update-fifo %{${plugin_name}} %{${message}} }" | kak -p ${kak_session}
    ) > /dev/null 2>&1 < /dev/null & }
}

define-command -override \
-docstring "plug-list [<noupdate>]: list all installed plugins in *plug* buffer. Chacks updates by default unless <noupdate> is specified." \
plug-list -params ..1 %{ evaluate-commands -try-client %opt{toolsclient} %sh{
    noupdate=$1
    fifo=$(mktemp -d "${TMPDIR:-/tmp}"/plug-kak.XXXXXXXX)/fifo
    plug_log=$(mktemp "${TMPDIR:-/tmp}"/plug-log.XXXXXXXX)
    mkfifo ${fifo}

    printf "%s\n" "edit! -fifo ${fifo} *plug*
                   set-option window filetype plug
                   hook -always -once buffer BufCloseFifo .* %{ nop %sh{ rm -r ${fifo%/*} } }
                   map buffer normal '<ret>' ':<space>plug-fifo-operate<ret>'"

    # get those plugins which were loaded by plug.kak
    eval "set -- ${kak_opt_plug_plugins}"
    while [ $# -gt 0 ]; do
        if [ -d "${kak_opt_plug_install_dir}/${1##*/}" ]; then
            printf "%s: Installed\n" "$1" >> ${plug_log}
        else
            printf "%s: Not installed\n" "$1" >> ${plug_log}
        fi
        shift
    done

    # get those plugins which have a directory at installation path, but wasn't mentioned in any config file
    for exitsting_plugin in $(printf "%s\n" ${kak_opt_plug_install_dir}/*); do
        if [ $(expr "${kak_opt_plug_plugins}" : ".*${exitsting_plugin##*/}.*") -eq 0 ]; then
            printf "%s: Not loaded\n" "${exitsting_plugin##*/}" >> ${plug_log}
        fi
    done

    ( sort ${plug_log} > ${fifo}; rm -rf ${plug_log} )  > /dev/null 2>&1 < /dev/null &

    if [ -z "${noupdate}" ]; then
        (
            [ -z "${GIT_TERMINAL_PROMPT}" ] && export GIT_TERMINAL_PROMPT=0
            eval "set -- ${kak_opt_plug_plugins}"
            while [ $# -gt 0 ]; do
                plugin_dir="${1##*/}"
                if [ -d "${kak_opt_plug_install_dir}/${plugin_dir}" ]; then (
                    cd ${kak_opt_plug_install_dir}/${plugin_dir}
                    git fetch > /dev/null 2>&1
                    status=$?
                    if [ ${status} -eq 0 ]; then
                        LOCAL=$(git rev-parse @{0})
                        REMOTE=$(git rev-parse @{u})
                        BASE=$(git merge-base @{0} @{u})

                        if [ ${LOCAL} = ${REMOTE} ]; then
                            message="Up to date"
                        elif [ ${LOCAL} = ${BASE} ]; then
                            message="Update available"
                        elif [ ${REMOTE} = ${BASE} ]; then
                            message="Local changes"
                        else
                            message="Installed"
                        fi
                    else
                        message="Fetch Error (${status})"
                    fi
                    printf "%s\n" "evaluate-commands -client ${kak_client} %{ plug-update-fifo %{$1} %{${message}} }" | kak -p ${kak_session}
                ) > /dev/null 2>&1 < /dev/null & fi
                shift
            done
        ) > /dev/null 2>&1 < /dev/null &
    fi

}}

define-command -override \
-docstring "operate on *plug* buffer contents based on current cursor position" \
plug-fifo-operate %{ evaluate-commands -save-regs t %{
    execute-keys -save-regs '' "<a-h><a-l>"
    set-register t %val{selection}
    evaluate-commands %sh{
        plugin="${kak_reg_t%:*}"
        if [ -d "${kak_opt_plug_install_dir}/${plugin##*/}" ]; then
            printf "%s\n" "plug-update ${plugin}'"
        else
            printf "%s\n" "plug-install ${plugin}'"
        fi
    }
}}

define-command -override \
-docstring "plug-update-fifo <plugin> <message>" \
plug-update-fifo -params 2 %{ evaluate-commands -buffer *plug* -save-regs "/""" %{ try %{
    set-register / "%arg{1}: "
    set-register dquote %arg{2}
    execute-keys /<ret>lGlR
}}}
