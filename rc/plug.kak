# Author: Andrey Listopadov
# plug.kak is a plugin manager for Kakoune. It can install plugins, keep them updated, configure and build dependencies
# https://github.com/andreyorst/plug.kak

# Public options
declare-option -docstring \
"Path where plugins should be installed.

    Defaults to the plug.kak installation directory" \
str plug_install_dir %sh{ echo "${kak_source%%/rc*}/../" }

declare-option -docstring \
"Default domain to access git repositories. Can be changed to any preferred domain, like gitlab, bitbucket, gitea, etc.

    Default value: 'https://github.com'" \
str plug_git_domain 'https://github.com'

declare-option -docstring \
"Profile plugin loading." \
bool plug_profile false

declare-option -docstring \
"Maximum amount of simultaneously active downloads when installing or updating all plugins
    Default value: 10
" \
int plug_max_active_downloads 10

declare-option -docstring \
"Always ensure that all plugins are installed. If this option specified, all uninstalled plugins are being installed when Kakoune starts." \
bool plug_always_ensure false

declare-option -docstring "name of the client in which utilities display information" \
str toolsclient

declare-option -docstring \
"Block UI until operation completes." \
bool plug_block_ui false

# Private options
declare-option -hidden -docstring \
"Path to plug.sh script." \
str plug_sh_source %sh{ echo "${kak_source%%.kak}.sh" }

declare-option -hidden -docstring \
"Array of all plugins, mentioned in any configuration file.
Empty by default, and erased on reload of main Kakoune configuration, to track if some plugins were disabled
Should not be modified by user." \
str plug_plugins ""

declare-option -hidden -docstring \
"List of loaded plugins. Has no default value.
Should not be cleared during update of configuration files. Should not be modified by user." \
str plug_loaded_plugins ""

declare-option -docstring \
"Whether or not to report errors in config blocks. Defaults to true." \
bool plug_report_conf_errors true

declare-option -hidden -docstring \
"This will be set if there are any errors with a plugin's config block. Has no default value.
Should not be cleared during update of configuration files. Should not be modified by user." \
str plug_conf_errors ""

# since we want to add highlighters to kak filetype we need to require kak module
# using `try' here since kakrc module may not be available in rare cases
try %@
    require-module kak

    try %$
        add-highlighter shared/kakrc/code/plug_keywords   regex '\b(plug|plug-chain|do|config|domain|defer|demand|load-path|branch|tag|commit|comment)(?=[ \t])' 0:keyword
        add-highlighter shared/kakrc/code/plug_attributes regex '(?<=[ \t])(noload|ensure|theme)\b' 0:attribute
        add-highlighter shared/kakrc/plug_post_hooks1     region -recurse '\{' '\bdo\K\h+%\{' '\}' ref sh
        add-highlighter shared/kakrc/plug_post_hooks2     region -recurse '\[' '\bdo\K\h+%\[' '\]' ref sh
        add-highlighter shared/kakrc/plug_post_hooks3     region -recurse '\(' '\bdo\K\h+%\(' '\)' ref sh
        add-highlighter shared/kakrc/plug_post_hooks4     region -recurse '<'  '\bdo\K\h+%<'  '>'  ref sh
    $ catch %$
        echo -debug "Error: plug.kak: can't declare highlighters for 'kak' filetype: %val{error}"
    $
@ catch %{
    echo -debug "Error: plug.kak: can't require 'kak' module to declare highlighters for plug.kak. Check if kakrc.kak is available in your autoload."
}

# *plug* highlighters
try %{
    add-highlighter shared/plug_buffer group
    add-highlighter shared/plug_buffer/done          regex [^:]+:\h+(Up\h+to\h+date|Done|Installed)$                    1:string
    add-highlighter shared/plug_buffer/update        regex [^:]+:\h+(Update\h+available|Deleted)$                       1:keyword
    add-highlighter shared/plug_buffer/not_installed regex [^:]+:\h+(Not\h+(installed|loaded)|(\w+\h+)?Error([^\n]+)?)$ 1:red+b
    add-highlighter shared/plug_buffer/updating      regex [^:]+:\h+(Installing|Updating|Local\h+changes)$              1:type
    add-highlighter shared/plug_buffer/working       regex [^:]+:\h+(Running\h+post-update\h+hooks|Waiting[^\n]+)$      1:attribute
} catch %{
    echo -debug "Error: plug.kak: Can't declare highlighters for *plug* buffer: %val{error}"
}

hook -group plug-syntax global WinSetOption filetype=plug %{
    add-highlighter buffer/plug_buffer ref plug_buffer
    hook -always -once window WinSetOption filetype=.* %{
        remove-highlighter buffer/plug_buffer
    }
}

define-command -override -docstring \
"plug <plugin> [<switches>]: manage <plugin> from ""%opt{plug_install_dir}""
Switches:
    branch (tag, commit) <str>      checkout to <str> before loading plugin
    noload                          do not source plugin files
    subset <subset>                 source only <subset> of plugin files
    load-path <path>                path for loading plugin from foreign location
    defer <module> <configurations> load plugin <configurations> only when <module> is loaded
    config <configurations>         plugin <configurations>" \
plug -params 1.. -shell-script-candidates %{ ls -1 ${kak_opt_plug_install_dir} } %{ try %{
    evaluate-commands %sh{
        # $kak_client
        # $kak_config
        # $kak_opt_plug_always_ensure
        # $kak_opt_plug_git_domain
        # $kak_opt_plug_install_dir
        # $kak_opt_plug_loaded_plugins
        # $kak_opt_plug_max_active_downloads
        # $kak_opt_plug_plugin
        # $kak_opt_plug_plugins
        # $kak_opt_plug_profile
        # $kak_opt_plug_block_ui
        # $kak_opt_plug_report_conf_errors
        # $kak_opt_plug_conf_errors
        # $kak_session

        . "${kak_opt_plug_sh_source}"
        plug "$@"
    }
}}

define-command -override plug-chain -params 0.. -docstring %{
  Chain plug commands (see docs, saves startup time by reducing sh calls)
} %{ try %{
    evaluate-commands %sh{
        # $kak_client
        # $kak_config
        # $kak_opt_plug_always_ensure
        # $kak_opt_plug_git_domain
        # $kak_opt_plug_install_dir
        # $kak_opt_plug_loaded_plugins
        # $kak_opt_plug_max_active_downloads
        # $kak_opt_plug_plugin
        # $kak_opt_plug_plugins
        # $kak_opt_plug_profile
        # $kak_opt_plug_block_ui
        # $kak_opt_plug_report_conf_errors
        # $kak_opt_plug_conf_errors
        # $kak_session

        set -u
        . "${kak_opt_plug_sh_source}"
        plug1() {
          for _plug_param; do
            # reset "$@" on 1st iteration; args still in 'for'
            [ "$_plug_processed_args" != 0 ] || set --
            _plug_processed_args=$((_plug_processed_args + 1))
            [ plug != "$_plug_param" ] || break
            set -- "$@" "$_plug_param"
          done
          [ $# = 0 ] || plug "$@"  # subshell would be safer, but slower
        }
        while [ "$#" != 0 ]; do
          _plug_processed_args=0
          plug1 "$@"
          shift "$_plug_processed_args"
        done
    }
}}

define-command -override -docstring \
"plug-install [<plugin>] [<noload>]: install <plugin>.
If <plugin> omitted installs all plugins mentioned in configuration
files.  If <noload> is supplied skip loading the plugin." \
plug-install -params ..2 %{ nop %sh{
    # $kak_client
    # $kak_config
    # $kak_opt_plug_always_ensure
    # $kak_opt_plug_git_domain
    # $kak_opt_plug_install_dir
    # $kak_opt_plug_loaded_plugins
    # $kak_opt_plug_max_active_downloads
    # $kak_opt_plug_plugin
    # $kak_opt_plug_plugins
    # $kak_opt_plug_profile
    # $kak_opt_plug_block_ui
    # $kak_opt_plug_report_conf_errors
    # $kak_opt_plug_conf_errors
    # $kak_session

    . "${kak_opt_plug_sh_source}"
    plug_install "$@"
}}

define-command -override -docstring \
"plug-update [<plugin>]: Update plugin.
If <plugin> omitted all installed plugins are updated" \
plug-update -params ..1 -shell-script-candidates %{ printf "%s\n" ${kak_opt_plug_plugins} | tr ' ' '\n' } %{
    evaluate-commands %sh{
        # $kak_client
        # $kak_config
        # $kak_opt_plug_always_ensure
        # $kak_opt_plug_git_domain
        # $kak_opt_plug_install_dir
        # $kak_opt_plug_loaded_plugins
        # $kak_opt_plug_max_active_downloads
        # $kak_opt_plug_plugin
        # $kak_opt_plug_plugins
        # $kak_opt_plug_profile
        # $kak_opt_plug_block_ui
        # $kak_opt_plug_report_conf_errors
        # $kak_opt_plug_conf_errors
        # $kak_session

        . "${kak_opt_plug_sh_source}"
        plug_update "$@"
}}

define-command -override -docstring \
"plug-clean [<plugin>]: delete <plugin>.
If <plugin> omitted deletes all plugins that are installed but not presented in configuration files" \
plug-clean -params ..1 -shell-script-candidates %{ ls -1 ${kak_opt_plug_install_dir} } %{ nop %sh{
    # $kak_client
    # $kak_config
    # $kak_opt_plug_always_ensure
    # $kak_opt_plug_git_domain
    # $kak_opt_plug_install_dir
    # $kak_opt_plug_loaded_plugins
    # $kak_opt_plug_max_active_downloads
    # $kak_opt_plug_plugin
    # $kak_opt_plug_plugins
    # $kak_opt_plug_profile
    # $kak_opt_plug_block_ui
    # $kak_opt_plug_report_conf_errors
    # $kak_opt_plug_conf_errors
    # $kak_session

    . "${kak_opt_plug_sh_source}"
    plug_clean "$@"
}}

define-command -override -hidden \
-docstring "plug-eval-hooks: wrapper for post update/install hooks" \
plug-eval-hooks -params 1 %{ nop %sh{
    # $kak_client
    # $kak_config
    # $kak_opt_plug_always_ensure
    # $kak_opt_plug_git_domain
    # $kak_opt_plug_install_dir
    # $kak_opt_plug_loaded_plugins
    # $kak_opt_plug_max_active_downloads
    # $kak_opt_plug_plugin
    # $kak_opt_plug_plugins
    # $kak_opt_plug_profile
    # $kak_opt_plug_block_ui
    # $kak_opt_plug_report_conf_errors
    # $kak_opt_plug_conf_errors
    # $kak_session

    . "${kak_opt_plug_sh_source}"
    plug_eval_hooks "$@"
}}

define-command -override \
-docstring "plug-list [<noupdate>]: list all installed plugins in *plug* buffer. Checks updates by default unless <noupdate> is specified." \
plug-list -params ..1 %{ evaluate-commands -try-client %opt{toolsclient} %sh{
    # $kak_client
    # $kak_config
    # $kak_opt_plug_always_ensure
    # $kak_opt_plug_git_domain
    # $kak_opt_plug_install_dir
    # $kak_opt_plug_loaded_plugins
    # $kak_opt_plug_max_active_downloads
    # $kak_opt_plug_plugin
    # $kak_opt_plug_plugins
    # $kak_opt_plug_profile
    # $kak_opt_plug_block_ui
    # $kak_opt_plug_report_conf_errors
    # $kak_opt_plug_conf_errors
    # $kak_session

    . "${kak_opt_plug_sh_source}"
    plug_list "$@"
}}

define-command -hidden -override \
-docstring "operate on *plug* buffer contents based on current cursor position" \
plug-fifo-operate -params 1 %{ evaluate-commands -save-regs t %{
    execute-keys -save-regs '' "<a-h><a-l>"
    set-register t %val{selection}
    evaluate-commands %sh{
    # $kak_reg_t
    # $kak_client
    # $kak_config
    # $kak_opt_plug_always_ensure
    # $kak_opt_plug_git_domain
    # $kak_opt_plug_install_dir
    # $kak_opt_plug_loaded_plugins
    # $kak_opt_plug_max_active_downloads
    # $kak_opt_plug_plugin
    # $kak_opt_plug_plugins
    # $kak_opt_plug_profile
    # $kak_opt_plug_block_ui
    # $kak_opt_plug_report_conf_errors
    # $kak_opt_plug_conf_errors
    # $kak_session

    . "${kak_opt_plug_sh_source}"
    plug_fifo_operate "$@"
}}}

define-command -hidden -override \
plug-display-log -params 1 %{ evaluate-commands %sh{
    plugin_log="${TMPDIR:-/tmp}/${1##*/}-log"
    [ -s "${plugin_log}" ] && printf "%s\n" "edit! -existing -debug -readonly -scroll %{${plugin_log}}"
}}

define-command -override \
-docstring "displays help message" \
plug-show-help %{
    info -title "plug.kak Help" "h,j,k,l: Move
<ret>:   Update or Install plugin
I:       Install plugin
U:       Update plugin
D:       clean (Delete) plugin
L:       show Log, if any
R:       Run post-update hooks manually
H        show Help message"
}
