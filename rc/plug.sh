#!/usr/bin/env sh

# Author: Andrey Listopadov
# https://github.com/andreyorst/plug.kak
#
# plug.kak is a plugin manager for Kakoune. It can install plugins,
# keep them updated, configure and build dependencies.
#
# plug.sh contains a set of functions plug.kak calls via shell
# expansions.

plug () {
    [ "${kak_opt_plug_profile:-}" = "true" ] && profile_start=$(date +%s%N)
    plugin="${1%%.git}"
    shift
    plugin_name="${plugin##*/}"
    path_to_plugin="${kak_opt_plug_install_dir:?}/$plugin_name"
    build_dir="${kak_opt_plug_install_dir:?}/.build/$plugin_name"
    conf_file="$build_dir/config"
    hook_file="$build_dir/hooks"

    if [ "$(expr "${kak_opt_plug_loaded_plugins:-}" : ".*${plugin}.*")" -ne 0 ]; then
        printf "%s\n" "echo -markup %{{Information}${plugin_name} already loaded}"
        exit
    fi

    if [ "$(expr "${kak_opt_plug_plugins:-}" : ".*${plugin}.*")" -eq 0 ]; then
        printf "%s\n" "set-option -add global plug_plugins %{${plugin} }"
    fi

    while [ $# -gt 0 ]; do
        case $1 in
            (branch|tag|commit) checkout_type=$1; shift; checkout="$1" ;;
            (noload) noload=1 ;;
            (load-path) shift; path_to_plugin=$(printf "%s\n" "$1" | sed "s:^\s*~/:${HOME}/:") ;;
            (defer)
                shift; defer_module="$1"; shift;
                deferred_conf=$(printf "%s\n" "$1" | sed "s/@/@@/g")
                printf "%s\n" "hook global ModuleLoaded '${defer_module}' %@ ${deferred_conf} @" ;;
            (demand)
                shift; demand_module="$1"; shift
                demand_conf=$(printf "%s\n" "$1" | sed "s/@/@@/g")
                printf "%s\n" "hook global ModuleLoaded '${demand_module}' %@ ${demand_conf} @"
                configurations="${configurations}
                                require-module ${demand_module}" ;;
            ("do") shift; hooks="$hooks
                                 $1" ;;
            (ensure) ensure=1 ;;
            (theme)
                noload=1
                theme_hooks="mkdir -p ${kak_config:?}/colors
                             find . -type f -name '*.kak' -exec ln -sf \"\${PWD}/{}\" ${kak_config}/colors/ \;"
                hooks="$hooks
                       $theme_hooks" ;;
            (domain) shift; domains="${domains} %{${plugin_name}} %{$1}" ;;
            (dept-sort|subset)
                printf "%s\n" "echo -debug %{Error: plug.kak: '${plugin_name}': keyword '$1' is no longer supported. Use the module system instead}"
                exit 1 ;;
            (no-depth-sort) printf "%s\n" "echo -debug %{Warning: plug.kak: '${plugin_name}': use of deprecated '$1' keyword which has no effect}" ;;
            (config) shift; configurations="${configurations} $1" ;;
            (*) configurations="${configurations} $1" ;;
        esac
        shift
    done

    mkdir -p "$build_dir"
    printf "%s\n" "$configurations" > "$conf_file"
    printf "%s\n" "$hooks" > "$hook_file"

    [ -n "${domains}" ] && printf "%s\n" "set-option -add global plug_domains ${domains}"

    if [ -d "${path_to_plugin}" ]; then
        if [ -n "${checkout}" ]; then
            (
                cd "${path_to_plugin}" || exit
                [ -z "${GIT_TERMINAL_PROMPT}" ] && export GIT_TERMINAL_PROMPT=0
                if [ "${checkout_type}" = "branch" ]; then
                    [ "$(git branch --show-current)" != "${checkout}" ] && git fetch >/dev/null 2>&1
                fi
                git checkout "${checkout}" >/dev/null 2>&1
            )
        fi
        plug_load "$plugin" "$noload"
    else
        if [ -n "${ensure}" ] || [ "${kak_opt_plug_always_ensure:-}" = "true" ]; then
            plug_install "$plugin" "$noload"
        fi
    fi
    if  [ "${kak_opt_plug_profile}" = "true" ]; then
        profile_end=$(date +%s%N)
        printf "%s\n" "echo -debug %{'$plugin_name' loaded in $(((profile_end-profile_start)/1000000)) ms}"
    fi
}

plug_install () {
    (
        plugin="${1%%.git}"
        noload=$2
        plugin_name="${plugin##*/}"
        jobs=$(mktemp "${TMPDIR:-/tmp}"/plug.kak.jobs.XXXXXX)

        [ -z "${GIT_TERMINAL_PROMPT}" ] && export GIT_TERMINAL_PROMPT=0

        if [ ! -d "${kak_opt_plug_install_dir}" ]; then
            if ! mkdir -p "${kak_opt_plug_install_dir}" >/dev/null 2>&1; then
                printf "%s\n" "evaluate-commands -client ${kak_client:-client0} echo -debug 'Error: plug.kak: unable to create directory for plugins'" | kak -p "${kak_session:?}"
                exit
            fi
        fi

        printf "%s\n" "evaluate-commands -client ${kak_client:-client0} %{ try %{ buffer *plug* } catch %{ plug-list noupdate } }" | kak -p "${kak_session}"
        sleep 0.3

        lockfile="${kak_opt_plug_install_dir}/.${plugin_name:-global}.plug.kak.lock"
        if [ -d "${lockfile}" ]; then
            plug_fifo_update "${plugin_name}" "Waiting for .plug.kak.lock"
        fi

        # this creates the lockfile for a plugin, if specified to prevent several processes of installation
        # of the same plugin, but will allow install different plugins without waiting for eachother.
        # Should be fine, since different plugins doesn't interfere with eachother.
        while ! mkdir "${lockfile}" 2>/dev/null; do sleep 1; done
        trap "rmdir '${lockfile}'" EXIT

        # if plugin specified as an argument add it to the *plug* buffer, if it isn't there already
        # otherwise update all plugins
        if [ -n "${plugin}" ]; then
            plugin_list=${plugin}
            printf "%s\n" "
                evaluate-commands -buffer *plug* %{ try %{
                    execute-keys /${plugin}<ret>
                } catch %{
                    execute-keys gjO${plugin}:<space>Not<space>installed<esc>
                }}" | kak -p "${kak_session}"
            sleep 0.2
        else
            plugin_list=${kak_opt_plug_plugins}
        fi

        for plugin in ${plugin_list}; do
            plugin_name="${plugin##*/}"
            git_domain=${kak_opt_plug_git_domain:?}

            eval "set -- ${kak_quoted_opt_plug_domains:-}"
            while [ $# -ne 0 ]; do
                if [ "$1" = "${plugin_name}" ]; then
                    git_domain="https://$2"
                    break
                fi
                shift
            done

            if [ ! -d "${kak_opt_plug_install_dir}/${plugin_name}" ]; then
                (
                    plugin_log="${TMPDIR:-/tmp}/${plugin_name}-log"
                    printf "%s\n" "hook global -always KakEnd .* %{ nop %sh{rm -rf \"${plugin_log}\"}} " | kak -p "${kak_session}"
                    plug_fifo_update "${plugin_name}" "Installing"
                    cd "${kak_opt_plug_install_dir}" || exit
                    case ${plugin} in
                        (http*|git*)
                            git clone "${plugin}" "${plugin_name}" >> "${plugin_log}" 2>&1 ;;
                        (*)
                            git clone "${git_domain}/${plugin}" "${plugin_name}" >> "${plugin_log}" 2>&1 ;;
                    esac
                    status=$?
                    if [ ${status} -ne 0 ]; then
                        plug_fifo_update "${plugin_name}" "Download Error (${status})"
                    else
                        plug_eval_hooks "$plugin_name"
                        wait
                        plug_load "$plugin" "$noload" | kak -p "${kak_session:?}"
                    fi
                ) > /dev/null 2>&1 < /dev/null &
            fi
            # this is a hacky way to measure amount of active processes. We need this
            # because dash shell has this long term bug: https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=482999
            jobs > "${jobs}"; active=$(wc -l < "${jobs}")
            while [ "${active}" -ge "${kak_opt_plug_max_active_downloads:?}" ]; do
                sleep 1
                jobs > "${jobs}"; active=$(wc -l < "${jobs}")
            done
        done
        wait
        rm -rf "${jobs}"
    ) > /dev/null 2>&1 < /dev/null &
}

plug_load() {
    plugin="${1%%.git}"
    noload=$2
    plugin_name="${plugin##*/}"
    path_to_plugin="${kak_opt_plug_install_dir:?}/$plugin_name"
    build_dir="${kak_opt_plug_install_dir:?}/.build/$plugin_name"
    conf_file="$build_dir/config"

    if [ -z "${noload}" ]; then
        find -L "${path_to_plugin}" -path '*/.git' -prune -o -type f -name '*.kak' -exec printf 'source "%s"\n' {} \;
    fi
    printf "%s\n" "source $conf_file"
    printf "%s\n" "set-option -add global plug_loaded_plugins %{${plugin} }"
}

plug_update () {
    (
        plugin=$1
        plugin_name="${plugin##*/}"
        jobs=$(mktemp "${TMPDIR:-/tmp}"/jobs.XXXXXX)

        [ -z "${GIT_TERMINAL_PROMPT}" ] && export GIT_TERMINAL_PROMPT=0

        printf "%s\n" "evaluate-commands -client ${kak_client:-client0} %{ try %{ buffer *plug* } catch %{ plug-list noupdate } }" | kak -p "${kak_session}"

        lockfile="${kak_opt_plug_install_dir}/.${plugin_name:-global}.plug.kak.lock"
        if [ -d "${lockfile}" ]; then
            plug_fifo_update "${plugin##*/}" "Waiting for .plug.kak.lock"
        fi

        while ! mkdir "${lockfile}" 2>/dev/null; do sleep 1; done
        trap "rmdir '${lockfile}'" EXIT

        [ -n "${plugin}" ] && plugin_list=${plugin} || plugin_list=${kak_opt_plug_plugins}
        for plugin in ${plugin_list}; do
            plugin_name="${plugin##*/}"
            if [ -d "${kak_opt_plug_install_dir}/${plugin_name}" ]; then
                (
                    plugin_log="${TMPDIR:-/tmp}/${plugin_name}-log"
                    printf "%s\n" "hook global -always KakEnd .* %{ nop %sh{rm -rf ${plugin_log}}} " | kak -p "${kak_session}"
                    plug_fifo_update "${plugin_name}" "Updating"
                    cd "${kak_opt_plug_install_dir}/${plugin_name}" && rev=$(git rev-parse HEAD) && git pull >> "${plugin_log}" 2>&1
                    status=$?
                    if [ ${status} -ne 0 ]; then
                        plug_fifo_update "${plugin_name}" "Update Error (${status})"
                    else
                        if [ "${rev}" != "$(git rev-parse HEAD)" ]; then
                            printf "%s\n" "evaluate-commands -client ${kak_client:-client0} plug-eval-hooks ${plugin_name}" | kak -p "${kak_session}"
                        else
                            plug_fifo_update "${plugin_name}" "Done"
                        fi
                    fi
                ) > /dev/null 2>&1 < /dev/null &
            fi
            jobs > "${jobs}"; active=$(wc -l < "${jobs}")
            # TODO: re-check this
            # for some reason I need to multiply the amount of jobs by five here.
            while [ "${active}" -ge $((kak_opt_plug_max_active_downloads * 5)) ]; do
                sleep 1
                jobs > "${jobs}"; active=$(wc -l < "${jobs}")
            done
        done
        rm -rf "${jobs}"
        wait
    ) > /dev/null 2>&1 < /dev/null &
}


plug_clean () {
    (
        plugin="${1%%.git}"
        plugin_name="${plugin##*/}"

        printf "%s\n" "evaluate-commands -client ${kak_client:-client0} %{ try %{ buffer *plug* } catch %{ plug-list noupdate } }" | kak -p "${kak_session}"

        lockfile="${kak_opt_plug_install_dir}/.${plugin_name:-global}.plug.kak.lock"
        if [ -d "${lockfile}" ]; then
            plug_fifo_update "${plugin_name}" "Waiting for .plug.kak.lock"
        fi

        while ! mkdir "${lockfile}" 2>/dev/null; do sleep 1; done
        trap "rmdir '${lockfile}'" EXIT

        if [ -n "${plugin}" ]; then
            if [ -d "${kak_opt_plug_install_dir}/${plugin_name}" ]; then
                (
                    cd "${kak_opt_plug_install_dir}" && rm -rf "${plugin_name}"
                    plug_fifo_update "${plugin_name}" "Deleted"
                )
            else
                printf "%s\n" "evaluate-commands -client ${kak_client:-client0} echo -markup %{{Error}No such plugin '${plugin}'}" | kak -p "${kak_session}"
                exit
            fi
        else
            for installed_plugin in $(printf "%s\n" "${kak_opt_plug_install_dir}"/*); do
                skip=
                for enabled_plugin in ${kak_opt_plug_plugins}; do
                    [ "${installed_plugin##*/}" = "${enabled_plugin##*/}" ] && { skip=1; break; }
                done
                [ "${skip}" = "1" ] || plugins_to_remove=${plugins_to_remove}" ${installed_plugin}"
            done
            for plugin in ${plugins_to_remove}; do
                plug_fifo_update "${plugin##*/}" "Deleted"
                rm -rf "${plugin}"
            done
        fi
    ) > /dev/null 2>&1 < /dev/null &
}

plug_eval_hooks () {
    (
        plugin="${1%%.git}"
        plugin_name="${plugin##*/}"
        path_to_plugin="${kak_opt_plug_install_dir:?}/$plugin_name"
        build_dir="${kak_opt_plug_install_dir:?}/.build/$plugin_name"
        hook_file="$build_dir/hooks"

        plugin_log="${TMPDIR:-/tmp}/${plugin_name}-log"
        cd "$path_to_plugin" || exit

        printf "%s\n" "hook global -always KakEnd .* %{ nop %sh{rm -rf ${plugin_log}}}" | kak -p "${kak_session}"
        plug_fifo_update "${plugin_name}" "Running post-update hooks"

        [ -e "$hook_file" ] && (. "$hook_file" > "$plugin_log" 2>&1)
        status=$?
        [ ${status} -ne 0 ] && message="Error (${status})" || message="Done"

        plug_fifo_update "${plugin_name}" "${message}"
    ) > /dev/null 2>&1 < /dev/null &
}

plug_list () {
    noupdate=$1
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/plug-kak.XXXXXXXX")
    fifo="${tmp}/fifo"
    plug_buffer="${tmp}/plug-buffer"
    mkfifo "${fifo}"

    printf "%s\n" "edit! -fifo ${fifo} *plug*
                   set-option buffer filetype plug
                   plug-show-help
                   hook -always -once buffer BufCloseFifo .* %{ nop %sh{ rm -rf ${tmp} } }
                   map buffer normal '<ret>' ':<space>plug-fifo-operate install-update<ret>'
                   map buffer normal 'H' ':<space>plug-show-help<ret>'
                   map buffer normal 'U' ':<space>plug-fifo-operate update<ret>'
                   map buffer normal 'I' ':<space>plug-fifo-operate install<ret>'
                   map buffer normal 'L' ':<space>plug-fifo-operate log<ret>'
                   map buffer normal 'D' ':<space>plug-fifo-operate clean<ret>'
                   map buffer normal 'R' ':<space>plug-fifo-operate hooks<ret>'"

    # get those plugins which were loaded by plug.kak
    eval "set -- ${kak_opt_plug_plugins}"
    while [ $# -gt 0 ]; do
        if [ -d "${kak_opt_plug_install_dir}/${1##*/}" ]; then
            printf "%s: Installed\n" "$1" >> "${plug_buffer}"
        else
            printf "%s: Not installed\n" "$1" >> "${plug_buffer}"
        fi
        shift
    done

    # get those plugins which have a directory at installation path, but wasn't mentioned in any config file
    for exitsting_plugin in $(printf "%s\n" "${kak_opt_plug_install_dir}"/*); do
        if [ "$(expr "${kak_opt_plug_plugins}" : ".*${exitsting_plugin##*/}.*")" -eq 0 ]; then
            printf "%s: Not loaded\n" "${exitsting_plugin##*/}" >> "${plug_buffer}"
        fi
    done

    ( sort "${plug_buffer}" > "${fifo}" )  > /dev/null 2>&1 < /dev/null &

    if [ -z "${noupdate}" ]; then
        (
            [ -z "${GIT_TERMINAL_PROMPT}" ] && export GIT_TERMINAL_PROMPT=0
            eval "set -- ${kak_opt_plug_plugins}"
            while [ $# -gt 0 ]; do
                plugin_dir="${1##*/}"
                if [ -d "${kak_opt_plug_install_dir}/${plugin_dir}" ]; then (
                    cd "${kak_opt_plug_install_dir}/${plugin_dir}" || exit
                    git fetch > /dev/null 2>&1
                    status=$?
                    if [ ${status} -eq 0 ]; then
                        LOCAL=$(git rev-parse "@{0}")
                        REMOTE=$(git rev-parse "@{u}")
                        BASE=$(git merge-base "@{0}" "@{u}")

                        if [ "${LOCAL}" = "${REMOTE}" ]; then
                            message="Up to date"
                        elif [ "${LOCAL}" = "${BASE}" ]; then
                            message="Update available"
                        elif [ "${REMOTE}" = "${BASE}" ]; then
                            message="Local changes"
                        else
                            message="Installed"
                        fi
                    else
                        message="Fetch Error (${status})"
                    fi
                    plug_fifo_update "$1" "${message}"
                ) > /dev/null 2>&1 < /dev/null & fi
                shift
            done
        ) > /dev/null 2>&1 < /dev/null &
    fi
}

plug_fifo_operate() {
    plugin="${kak_reg_t%:*}"
    case $1 in
        (install-update)
            if [ -d "${kak_opt_plug_install_dir}/${plugin##*/}" ]; then
                plug_update "${plugin}"
            else
                plug_install "${plugin}"
            fi ;;
        (update)
            if [ -d "${kak_opt_plug_install_dir}/${plugin##*/}" ]; then
                plug_update "${plugin}"
            else
                printf "%s\n" "echo -markup %{{Information}'${plugin}' is not installed}"
            fi ;;
        (install)
            if [ ! -d "${kak_opt_plug_install_dir}/${plugin##*/}" ]; then
                plug_install "${plugin}"
            else
                printf "%s\n" "echo -markup %{{Information}'${plugin}' already installed}"
            fi ;;
        (clean) plug_clean "${plugin}" ;;
        (log) plug_display_log "${plugin}" ;;
        (hooks) plug_eval_hooks "${plugin##*/}" ;;
        (*) ;;
    esac
}

plug_fifo_update() {
    printf "%s\n" "
        evaluate-commands -draft -buffer *plug* -save-regs \"/\"\"\" %{ try %{
            set-register / \"$1: \"
            set-register dquote %{$2}
            execute-keys -draft /<ret>lGlR
        }}" | kak -p "$kak_session"
}

plug_display_log() {
    plugin="${1%%.git}"
    plugin_name="${plugin##*/}"
    plugin_log="${TMPDIR:-/tmp}/${plugin-name}-log"
    [ -s "${plugin_log}" ] && printf "%s\n" "edit! -existing -debug -readonly -scroll %{${plugin_log}}" | kak -p "$kak_session"

}
