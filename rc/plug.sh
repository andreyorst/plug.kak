#!/usr/bin/env sh

# Author: Andrey Listopadov
# https://github.com/andreyorst/plug.kak
#
# plug.kak is a plugin manager for Kakoune. It can install plugins,
# keep them updated, configure and build dependencies.
#
# plug.sh contains a set of functions plug.kak calls via shell
# expansions.

plug_code_append () {
    eval "$1=\"\$$1
\$2\""
}

plug () {
    [ "${kak_opt_plug_profile:-}" = "true" ] && plug_save_timestamp profile_start
    plugin_arg=$1
    plugin="${1%%.git}"; plugin=${plugin%%/}
    shift
    plugin_name="${plugin##*/}"
    path_to_plugin="${kak_opt_plug_install_dir:?}/$plugin_name"
    build_dir="${kak_opt_plug_install_dir:?}/.build/$plugin_name"
    conf_file="$build_dir/config"
    hook_file="$build_dir/hooks"
    domain_file="$build_dir/domain"

    configurations= hooks= domain= checkout= checkout_type= noload= ensure=

    case "${kak_opt_plug_loaded_plugins:-}" in
      (*"$plugin"*)
        printf "%s\n" "echo -markup %{{Information}$plugin_name already loaded}"
        exit
        ;;
      (*)
        printf "%s\n" "set-option -add global plug_plugins %{$plugin }"
        ;;
    esac

    while [ $# -gt 0 ]; do
        case $1 in
            (branch|tag|commit) checkout_type=$1; shift; checkout=${1?} ;;
            (noload) noload=1 ;;
            (load-path) shift; eval "path_to_plugin=${1?}" ;;
            (comment) shift ;;
            (defer|demand)
                demand=$1
                shift; module=${1?}
                if [ $# -ge 2 ]; then
                    case "$2" in
                        (branch|tag|commit|noload|load-path|ensure|theme|domain|depth-sort|subset|no-depth-sort|config|defer|demand|comment)
                        ;;
                        (*)
                            shift
                            deferred=$1
                            case "$deferred" in (*[![:space:]]*)
                                case "$deferred" in (*'@'*)
                                    deferred=$(printf "%s\n" "$deferred" | sed "s/@/@@/g") ;;
                                esac
                                printf "%s\n" "hook global ModuleLoaded '$module' %@ $deferred @"
                            esac
                            [ "$demand" = demand ] && plug_code_append configurations "require-module $module" ;;
                    esac
                fi
                ;;
            ('do') shift; plug_code_append hooks "set -e
${1?}" ;;
            (ensure) ensure=1 ;;
            (theme)
                noload=1
                plug_code_append hooks "[ -d \"${kak_config:?}/colors\" ] || mkdir -p \"${kak_config}/colors\"; ln -sf \"\$PWD\" \"$kak_config/colors\""
            ;;
            (domain) shift; domain=${1?} ;;
            (depth-sort|subset)
                printf "%s\n" "echo -debug %{Error: plug.kak: '$plugin_name': keyword '$1' is no longer supported. Use the module system instead}"
                exit 1 ;;
            (no-depth-sort) printf "%s\n" "echo -debug %{Warning: plug.kak: '$plugin_name': use of deprecated '$1' keyword which has no effect}" ;;
            (config) shift; plug_code_append configurations "${1?}" ;;
            (*) plug_code_append configurations "$1" ;;
        esac
        shift
    done

    [ -d "$build_dir" ] || mkdir -p "$build_dir"
    rm -rf "$build_dir"/* "$build_dir"/.[!.]* "$build_dir"/..?*
    [ -n "$hooks" ] && printf "%s" "$hooks" > "$hook_file"
    [ -n "$domain" ] && printf "%s" "$domain" > "$domain_file"

    if [ -n "$configurations" ]; then
        if [ "${kak_opt_plug_report_conf_errors:-}" = "true" ]; then
            cat > "$conf_file" <<ERRHANDLE
try %{ $configurations } catch %{
    echo -debug "Error while evaluating '$plugin_name' configuration: %val{error}"

    set-option -add current plug_conf_errors "Error while evaluating '$plugin_name' configuration:"
    set-option -add current plug_conf_errors %sh{ printf "\n    " }
    set-option -add current plug_conf_errors %val{error}
    set-option -add current plug_conf_errors %sh{ printf "\n\n" }

    hook -once -group plug-conf-err global WinDisplay .* %{
        info -style modal -title "plug.kak error" "%opt{plug_conf_errors}"
        on-key %{
            info -style modal
            execute-keys -with-maps -with-hooks %val{key}
        }
    }
}
ERRHANDLE
        else
          printf "%s" "$configurations" > "$conf_file"
        fi
    fi

    if [ -d "$path_to_plugin" ]; then
        if [ -n "$checkout" ]; then
            (
                cd "$path_to_plugin" || exit
                # shellcheck disable=SC2030,SC2031
                [ -z "${GIT_TERMINAL_PROMPT:-}" ] && export GIT_TERMINAL_PROMPT=0
                if [ "$checkout_type" = "branch" ]; then
                    [ "$(git branch --show-current)" != "$checkout" ] && git fetch >/dev/null 2>&1
                fi
                git checkout "$checkout" >/dev/null 2>&1
            )
        fi
        plug_load "$plugin" "$path_to_plugin" "$noload"
        if  [ "$kak_opt_plug_profile" = "true" ]; then
            plug_save_timestamp profile_end
            profile_time=$(echo "scale=3; x=($profile_end-$profile_start)/1000; if(x<1) print 0; x" | bc -l)
            printf "%s\n" "echo -debug %{'$plugin_name' loaded in $profile_time sec}"
        fi
    else
        if [ -n "$ensure" ] || [ "${kak_opt_plug_always_ensure:-}" = "true" ]; then
            (
                plug_install "$plugin_arg" "$noload"
                wait
                if  [ "$kak_opt_plug_profile" = "true" ]; then
                    plug_save_timestamp profile_end
                    profile_time=$(echo "scale=3; x=($profile_end-$profile_start)/1000; if(x<1) print 0; x" | bc -l)
                    printf "%s\n" "echo -debug %{'$plugin_name' loaded in $profile_time sec}" | kak -p "${kak_session:?}"
                fi
            ) > /dev/null 2>&1 < /dev/null &
        fi
    fi
}

plug_install () {
    (
        plugin="${1%%.git}"; plugin=${plugin%%/}
        noload=$2
        plugin_name="${plugin##*/}"
        build_dir="${kak_opt_plug_install_dir:?}/.build/$plugin_name"
        domain_file="$build_dir/domain"

        # shellcheck disable=SC2030,SC2031
        [ -z "${GIT_TERMINAL_PROMPT:-}" ] && export GIT_TERMINAL_PROMPT=0

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

        # this creates the lock file for a plugin, if specified to
        # prevent several processes of installation of the same
        # plugin, but will allow install different plugins without
        # waiting for each other.  Should be fine, since different
        # plugins doesn't interfere with each other.
        while ! mkdir "${lockfile}" 2>/dev/null; do sleep 1; done
        # shellcheck disable=SC2064
        trap "rmdir '${lockfile}'" EXIT

        # if plugin specified as an argument add it to the *plug*
        # buffer, if it isn't there already otherwise update all
        # plugins
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
            [ -e "$domain_file" ] && git_domain="https://$(cat "$domain_file")" || git_domain=${kak_opt_plug_git_domain:?}
            if [ ! -d "${kak_opt_plug_install_dir}/${plugin_name}" ]; then
                (
                    plugin_log="${TMPDIR:-/tmp}/${plugin_name}-log"
                    printf "%s\n" "hook global -always KakEnd .* %{ nop %sh{rm -rf \"$plugin_log\"}} " | kak -p "${kak_session}"
                    plug_fifo_update "${plugin_name}" "Installing"
                    cd "${kak_opt_plug_install_dir}" || exit
                    case ${plugin} in
                        (https://*|http://*|*@*|file://*|ext::*)
                            git clone --recurse-submodules "${plugin}" "$plugin_name" >> "$plugin_log" 2>&1 ;;
                        (*)
                            git clone --recurse-submodules "$git_domain/$plugin" "$plugin_name" >> "$plugin_log" 2>&1 ;;
                    esac
                    status=$?
                    if [ ${status} -ne 0 ]; then
                        plug_fifo_update "$plugin_name" "Download Error ($status)"
                    else
                        plug_eval_hooks "$plugin_name"
                        wait
                        plug_load "$plugin" "${kak_opt_plug_install_dir:?}/$plugin_name" "$noload" | kak -p "${kak_session:?}"
                    fi
                ) > /dev/null 2>&1 < /dev/null &
            fi
            # this is a hacky way to measure amount of active
            # processes. We need this because dash shell has this long
            # term bug:
            # https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=482999
            jobs=$(mktemp "${TMPDIR:-/tmp}"/plug.kak.jobs.XXXXXX)
            jobs > "${jobs}"; active=$(wc -l < "${jobs}")
            while [ "${active}" -ge "${kak_opt_plug_max_active_downloads:?}" ]; do
                sleep 1
                jobs > "${jobs}"; active=$(wc -l < "${jobs}")
            done
            rm -rf "${jobs}"
        done
        wait
    ) > /dev/null 2>&1 < /dev/null &
}

plug_load() {
    plugin="${1%%.git}"
    path_to_plugin=$2
    noload=$3
    plugin_name="${plugin##*/}"
    build_dir="${kak_opt_plug_install_dir:?}/.build/$plugin_name"
    conf_file="$build_dir/config"

    if [ -z "${noload}" ]; then
        find -L "${path_to_plugin}" -path '*/.git' -prune -o -type f -name '*.kak' -exec printf 'source "%s"\n' {} +
    fi
    [ -e "$conf_file" ] && printf "%s\n" "source $conf_file"
    printf "%s\n" "set-option -add global plug_loaded_plugins %{${plugin} }"
}

plug_update () {
    (
        plugin="${1%%.git}"
        plugin_name="${plugin##*/}"

        # shellcheck disable=SC2030,SC2031
        [ -z "${GIT_TERMINAL_PROMPT:-}" ] && export GIT_TERMINAL_PROMPT=0

        printf "%s\n" "evaluate-commands -client ${kak_client:-client0} %{ try %{ buffer *plug* } catch %{ plug-list noupdate } }" | kak -p "${kak_session}"

        lockfile="${kak_opt_plug_install_dir}/.${plugin_name:-global}.plug.kak.lock"
        if [ -d "${lockfile}" ]; then
            plug_fifo_update "${plugin##*/}" "Waiting for .plug.kak.lock"
        fi

        while ! mkdir "${lockfile}" 2>/dev/null; do sleep 1; done
        # shellcheck disable=SC2064
        trap "rmdir '${lockfile}'" EXIT

        [ -n "${plugin}" ] && plugin_list=${plugin} || plugin_list=${kak_opt_plug_plugins}
        for plugin in ${plugin_list}; do
            plugin_name="${plugin##*/}"
            if [ -d "${kak_opt_plug_install_dir}/${plugin_name}" ]; then
                (
                    plugin_log="${TMPDIR:-/tmp}/${plugin_name}-log"
                    printf "%s\n" "hook global -always KakEnd .* %{ nop %sh{rm -rf ${plugin_log}}} " | kak -p "${kak_session}"
                    plug_fifo_update "${plugin_name}" "Updating"
                    cd "${kak_opt_plug_install_dir}/${plugin_name}" && rev=$(git rev-parse HEAD) && git pull --recurse-submodules >> "${plugin_log}" 2>&1
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
            jobs=$(mktemp "${TMPDIR:-/tmp}"/jobs.XXXXXX)
            jobs > "${jobs}"; active=$(wc -l < "${jobs}")
            # TODO: re-check this
            # For some reason I need to multiply the amount of jobs by five here.
            while [ "${active}" -ge $((kak_opt_plug_max_active_downloads * 5)) ]; do
                sleep 1
                jobs > "${jobs}"; active=$(wc -l < "${jobs}")
            done
            rm -rf "${jobs}"
        done
        wait
    ) > /dev/null 2>&1 < /dev/null &

    if [ "${kak_opt_plug_block_ui:-}" = "true" ]; then
        wait
    fi
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
        # shellcheck disable=SC2064
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

    if [ "$kak_opt_plug_block_ui" = "true" ]; then
        wait
    fi
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

        status=0
        if [ -e "$hook_file" ]; then
            # shellcheck disable=SC1090
            (. "$hook_file" >> "$plugin_log" 2>&1)
            status=$?
        fi
        [ ${status} -ne 0 ] && message="Error (${status})" || message="Done"

        plug_fifo_update "${plugin_name}" "${message}"
    ) > /dev/null 2>&1 < /dev/null &

    if [ "$kak_opt_plug_block_ui" = "true" ]; then
        wait
    fi
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

    # get those plugins which have a directory at installation path,
    # but wasn't mentioned in any config file
    for existing_plugin in "${kak_opt_plug_install_dir}"/*; do
        case "${kak_opt_plug_plugins}" in
          (*"${existing_plugin##*/}"*) ;;
          (*)
            printf "%s: Not loaded\n" "${existing_plugin##*/}" >> "${plug_buffer}"
            ;;
        esac
    done

    ( sort "${plug_buffer}" > "${fifo}" )  > /dev/null 2>&1 < /dev/null &

    if [ -z "${noupdate}" ]; then
        (
            # shellcheck disable=SC2030,SC2031
            [ -z "${GIT_TERMINAL_PROMPT:-}" ] && export GIT_TERMINAL_PROMPT=0
            eval "set -- ${kak_opt_plug_plugins}"
            while [ $# -gt 0 ]; do
                plugin_dir="${1##*/}"
                if [ -d "${kak_opt_plug_install_dir}/${plugin_dir}" ]; then (
                    cd "${kak_opt_plug_install_dir}/${plugin_dir}" || exit
                    git fetch > /dev/null 2>&1
                    status=$?
                    if [ ${status} -eq 0 ]; then
                        { IFS= read -r LOCAL; IFS= read -r REMOTE; IFS= read -r BASE; } <<EOF
$(
                        git rev-parse  @ '@{u}'  # prints 2 lines
                        git merge-base @ '@{u}'
)
EOF

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
                plug_install "${plugin}" true
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
        (log) printf "%s\n" "plug-display-log $plugin" ;;
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

plug_save_timestamp() {
  plug_tstamp=${EPOCHREALTIME:-}
  if [ -n "$plug_tstamp" ]; then
    plug_tstamp_ms=${plug_tstamp#*.}
    case "$plug_tstamp_ms" in
      (????*) plug_tstamp_ms=${plug_tstamp_ms%"${plug_tstamp_ms#???}"} ;;
      (???)   ;;
      (*)     plug_tstamp= ;;  # redo with date
    esac
    if [ -n "$plug_tstamp" ]; then
      plug_tstamp=${plug_tstamp%.*}${plug_tstamp_ms}
    fi
  fi
  : "${plug_tstamp:=$(date +%s%3N)}"
  if [ -n "$1" ]; then eval "$1=\$plug_tstamp"; fi
}

#  Spell-checker local dictionary
#  LocalWords:  Andrey Listopadov github kak usr config dir Kakoune
#  LocalWords:  expr ModuleLoaded mkdir ln PWD conf shellcheck noload
#  LocalWords:  TMPDIR tmp noupdate lockfile rmdir ret gjO esc KakEnd
#  LocalWords:  nop rf hacky eval fifo filetype BufCloseFifo regs
#  LocalWords:  dquote lGlR
