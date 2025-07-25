#! /bin/bash
#
# autossh.sh
# Copyright (C) 2025 fabriceluo <fabriceluo@outlook.com>
#
# Distributed under terms of the MIT license.
#

TEMP_STR=

DEPENDENCE_BINS=(ssh jq fzf sshpass)

USER_PASSWORD=
USER_NAME="root"
USER_HOST=
USER_PORT=22
USER_LABELS=""
USER_ALIAS=""

RUN_MODE_LOGIN="login"
RUN_MODE_PREVIEW="preview"
RUN_MODE_HEALTH="health"
RUN_MODE="login"

ROOT_USER_NAME="root"

PASSWORD_PROVIDER=""
PASSWORD_PROVIDER_USER="user"
PASSWORD_PROVIDER_DB="db"
PASSWORD_PROVIDER_AUTO="auto"
PASSWORD_PROVIDER_PUBKEY="public_key"

PUBLIC_KEY_PATH=~/.ssh/id_rsa.pub

HOST_RECORD_EXIST=1
HOST_RECORD_ERROR=0
HOST_RECORD_CONFIG=~/.autossh/autossh_db.conf
HOST_RECORD_CONFIG_TEMP="${HOST_RECORD_CONFIG}.temp"

PASSWORD_SUFFIX=""
PASSWORD_APPEND_SUFFIX=1

USER_PART_PASSWORD_VALID=1
USER_PART_PASSWORD_INDEX=0
USER_PART_PASSWORD_COUNT=0

SSH_AGENT=

SSH_AGENT_OPENSSH="ssh"
SSH_AGENT_SSHRC="sshrc"

LOGIN_TARGET=""
LOGIN_TARGET_REGEX='\w+@[0-2]?[0-9]{0,2}(\.[0-2]?[0-9]{0,2}){3}:[0-9]{1,}'
LOGIN_VERBOSE=0

declare -a USER_PART_PASSWORD_ARRAY

cmd_help() {
    echo "${0} usage:"
    echo "${0} [-p password] [-u user] [-i ip] [-c config_file] [-d] [-v] to login"
    echo "${0} [-h] to show this usage"
    echo "          -p password, login password"
    echo "          -u user, login user name"
    echo "          -i host, login host address"
    echo "          -c config_file, config file path"
    echo "          -d, disable append suffix, suffix:${PASSWORD_SUFFIX}"
    echo "          -r, use sshrc instead of ssh. sshrc can carry scripts"
    echo "          -P port, the ssh destination port"
    echo "          -l labels, the target labels. format: label1,label2,label3,..."
    echo "          -a alias, the target alias"
    echo "          -m mode, run mode. login|preview"
    echo "          -t target, target for preview"
    echo "          -v, verbose information"
    exit 1
}

init_db_config() {
    local config_dir
    test -e "${HOST_RECORD_CONFIG}" && return 0

    if ! config_dir=$(dirname "${HOST_RECORD_CONFIG}"); then
        echo "Get host database config failed"
        return 1
    fi

    if ! mkdir -p "$config_dir"; then
        echo "Create config dir failed"
        return 1
    fi
    cat <<EOF >"$HOST_RECORD_CONFIG"
{
    "PartPasswds": [
    ],
    "NodeRecords": {
    }
}
EOF
    return $?
}

load_db_config() {
    local part_lines

    if ! part_lines=$(jq -r ".PartPasswds[].password" "$HOST_RECORD_CONFIG"); then
        echo "Load db config failed"
        return 1
    fi

    USER_PART_PASSWORD_ARRAY=($part_lines)
    USER_PART_PASSWORD_INDEX=0
    USER_PART_PASSWORD_COUNT=${#USER_PART_PASSWORD_ARRAY[@]}
    return 0
}

get_record_index() {
    echo "${USER_NAME}@${USER_HOST}:${USER_PORT}"
    return 0
}

get_password_from_db() {
    local record_exist
    local record_index
    local record_passwd
    local record_labels
    local record_alias

    # 数据库中不存在，不再查询直接返回
    if [[ $HOST_RECORD_EXIST -eq 0 || $HOST_RECORD_ERROR -eq 1 ]]; then
        return 1
    fi

    # 先检查登录索引是否存在，存在才获取
    record_index=$(get_record_index)
    record_exist=$(jq ".NodeRecords|has(\"$record_index\")" "$HOST_RECORD_CONFIG")

    if [[ $record_exist == "false" ]]; then
        HOST_RECORD_EXIST=0
        return 1
    fi

    HOST_RECORD_EXIST=1
    # 获取记录信息
    record_passwd=$(jq -r ".NodeRecords.\"${record_index}\".password" "${HOST_RECORD_CONFIG}") || return 1
    record_labels=$(jq -r ".NodeRecords.\"${record_index}\".labels" "${HOST_RECORD_CONFIG}") || return 1
    record_alias=$(jq -r ".NodeRecords.\"${record_index}\".alias" "${HOST_RECORD_CONFIG}") || return 1

    USER_PASSWORD=$record_passwd
    USER_LABELS=$record_labels
    USER_ALIAS=$record_alias
    return 0
}

create_password_db_record() {
    # 调用更新的接口创建记录
    update_password_db_record
    return $?
}

update_password_db_record() {
    local record_index
    record_index=$(get_record_index)
    # 获取索引，更新索引对应的值
    jq ".NodeRecords.\"${record_index}\" |= {\"password\": \"$USER_PASSWORD\", \"labels\": \"$USER_LABELS\", \"alias\": \"$USER_ALIAS\"}" "$HOST_RECORD_CONFIG" >"$HOST_RECORD_CONFIG_TEMP" && mv -f "$HOST_RECORD_CONFIG_TEMP" "$HOST_RECORD_CONFIG"
    return $?
}

set_password_to_db() {
    # fixme add lock
    # 如果数据库中索引存在，更新，否则创建
    if [[ $HOST_RECORD_EXIST -eq 1 ]]; then
        update_password_db_record
    else
        create_password_db_record
    fi
}

get_password_from_user() {
    echo "Please input password for host(${USER_HOST}) of user(${USER_NAME})"
    echo -n "Password:"
    read -rse USER_PASSWORD
    echo ""
    return 0
}

get_password_from_part() {
    if [[ $USER_PART_PASSWORD_INDEX -ge $USER_PART_PASSWORD_COUNT ]]; then
        USER_PART_PASSWORD_INDEX=0
        USER_PART_PASSWORD_COUNT=0
        USER_PART_PASSWORD_VALID=0

        return 1
    fi

    local part_password="${USER_PART_PASSWORD_ARRAY[$USER_PART_PASSWORD_INDEX]}"
    USER_PART_PASSWORD_INDEX=$((USER_PART_PASSWORD_INDEX + 1))
    if [[ $PASSWORD_APPEND_SUFFIX -eq 1 ]]; then
        USER_PASSWORD="${part_password}${PASSWORD_SUFFIX}"
    else
        USER_PASSWORD="${part_password}"
    fi
    return 0
}

get_password() {
    # 从数据库中获取失败，需要手动输入
    if get_password_from_db; then
        PASSWORD_PROVIDER=$PASSWORD_PROVIDER_DB
        return 0
    fi

    if [[ -n $USER_PART_PASSWORD_VALID ]]; then
        get_password_from_part && return 0
    fi

    # 从用户输入
    if get_password_from_user; then
        PASSWORD_PROVIDER=$PASSWORD_PROVIDER_USER
        if [[ $PASSWORD_APPEND_SUFFIX -eq 1 ]]; then
            USER_PASSWORD="${USER_PASSWORD}${PASSWORD_SUFFIX}"
        fi
        return 0
    fi
    return 1
}

get_current_user_public_key() {
    if [[ ! -f ${PUBLIC_KEY_PATH} ]]; then
        echo "public key file(${PUBLIC_KEY_PATH}) is not exists"
        return 1
    fi

    cat "${PUBLIC_KEY_PATH}"
    return $?
}

get_remote_public_key_path() {
    if [[ "${USER_NAME}" == "${ROOT_USER_NAME}" ]]; then
        echo "/root/.ssh/authorized_keys"
    else
        echo "/home/${USER_NAME}/.ssh/authorized_keys"
    fi
    return 0
}

is_public_key_exist_in_remote() {
    local public_key=$1
    local remote_public_key_path
    local remote_public_keys

    if ! remote_public_key_path=$(get_remote_public_key_path); then
        echo "get remote public keys file path failed"
        return 1
    fi

    if ! login_run_command "test -f ${remote_public_key_path}"; then
        echo "remote public keys file(${remote_public_key_path}) is not exist"
        return 1
    fi

    if ! remote_public_keys=$(login_run_command "cat ${remote_public_key_path}"); then
        echo "get remote public keys failed"
        return 1
    fi

    if ! echo "${remote_public_keys}" | grep "${public_key}" >/dev/null 2>&1; then
        echo "public key on remote not found"
        return 1
    fi

    return 0
}

append_public_key_to_remote() {
    local public_key=$1
    local remote_public_key_path
    local remote_public_key_dir

    if ! remote_public_key_path=$(get_remote_public_key_path); then
        echo "get remote public keys file path failed"
        return 1
    fi

    if ! remote_public_key_dir=$(dirname "${remote_public_key_path}"); then
        echo "get remote public key file dir failed"
        return 1
    fi

    if ! login_run_command "mkdir -p \"${remote_public_key_dir}\""; then
        echo "prepare public keys file dir failed"
        return 1
    fi

    if ! login_run_command "echo \"${public_key}\" >> ${remote_public_key_path}" >/dev/null 2>&1; then
        echo "append public key to remote host failed"
        return 1
    fi

    echo "append public key to host(${USER_HOST}) success"
    return 0
}

sync_public_key() {
    local public_key=

    if ! public_key=$(get_current_user_public_key); then
        echo "get public key failed"
        return 1
    fi

    if is_public_key_exist_in_remote "${public_key}"; then
        return 0
    fi

    append_public_key_to_remote "${public_key}"
    return $?
}

login_run_command() {
    local command=$1

    export SSHPASS=$USER_PASSWORD
    sshpass -e ssh -p $USER_PORT -o StrictHostKeyChecking=no $USER_NAME@$USER_HOST "${command}"

    return $?
}

test_password() {
    # 在远程主机上执行exit 0命令，执行成功说明密码正确
    login_run_command "exit 0"
    return $?
}

login_with_openssh() {
    sshpass -e ssh -p $USER_PORT -o StrictHostKeyChecking=no $USER_NAME@$USER_HOST
    return $?
}

login_with_sshrc() {
    # fixme: 增加对port的支持
    sshrc $USER_NAME@$USER_HOST
    return $?
}

login_with_password() {
    # 导出环境变量，避免泄露和供sshrc使用
    export SSHPASS=$USER_PASSWORD

    [[ $LOGIN_VERBOSE -ne 0 ]] && echo "user(${USER_NAME}) login to (${USER_HOST}) with password:${USER_PASSWORD}"
    if [[ "${SSH_AGENT}" == "${SSH_AGENT_OPENSSH}" ]]; then
        login_with_openssh
    elif [[ "${SSH_AGENT}" == "${SSH_AGENT_SSHRC}" ]]; then
        login_with_sshrc
    else
        echo "login agent not support:$SSH_AGENT"
        exit 1
    fi
    return $?
}

get_login_target_from_db() {
    local targets
    local db_targets

    db_targets=$(jq -r '.NodeRecords | keys | .[]' "$HOST_RECORD_CONFIG")

    targets=$(echo "$db_targets" | fzf --print-query --preview "bash ${0} -m preview -t {}")
    local errcode=$?
    if [[ $errcode -eq 130 ]]; then
        exit 1
    fi

    if [[ $errcode -eq 0 ]]; then
        targets=$(echo "$targets" | sed -n '2p')
    fi

    LOGIN_TARGET=$targets
    return 0
}

init_login_target() {
    # 解析target是否正确，不正确需要重新输入
    test -z "$LOGIN_TARGET" && return 1

    [[ ! $LOGIN_TARGET =~ $LOGIN_TARGET_REGEX ]] && return 1

    # target template: mike@192.168.2.1:22
    TEMP_STR="${LOGIN_TARGET%%:*}"

    USER_NAME="${TEMP_STR%%@*}"
    USER_HOST="${TEMP_STR#*@}"

    USER_PORT="${LOGIN_TARGET##*:}"

    return 0
}

get_login_target() {
    # 先从数据库中获取，获取失败或初始化失败时，重新获取
    while true; do

        if ! get_login_target_from_db; then
            continue
        fi

        if init_login_target; then
            return 0
        fi
    done

    return 1
}

auto_login() {
    local errcode=$?
    # 不断获取密码，重试登录
    while true; do
        if [[ -n $USER_PASSWORD ]]; then
            PASSWORD_PROVIDER=$PASSWORD_PROVIDER_USER
        else
            get_password
        fi

        test_password
        errcode=$?
        if [[ $errcode -ne 0 ]]; then
            # 密码错误时，清理掉用户的密码，重新获取密码
            USER_PASSWORD=""
            if [[ $errcode -eq 5 && "${PASSWORD_PROVIDER}" == "${PASSWORD_PROVIDER_DB}" ]]; then
                HOST_RECORD_ERROR=1
            fi
        else
            if [[ "${PASSWORD_PROVIDER}" != "${PASSWORD_PROVIDER_DB}" || "${HOST_RECORD_ERROR}" ]]; then
                set_password_to_db || echo "Password save failed"
                sync_public_key || echo "Sync public key failed"
            fi
            break
        fi

    done

    login_with_password
    return $?
}

cmd_login() {
    # 传入了密码，同时需要增加后缀
    if [[ $PASSWORD_APPEND_SUFFIX -eq 1 && -n $USER_PASSWORD ]]; then
        USER_PASSWORD="${USER_PASSWORD}${PASSWORD_SUFFIX}"
    fi
    init_db_config || exit 1

    # 当没有传IP或者IP为空时，从数据库中获取
    if [[ -z $USER_HOST ]]; then
        get_login_target || exit 1
    fi

    load_db_config || exit 1
    auto_login
}

cmd_preview() {
    if [[ -z $LOGIN_TARGET ]]; then
        cmd_help
    fi
    if ! init_login_target; then
        return 1
    fi

    if ! get_password_from_db; then
        return 1
    fi

    echo "      ${LOGIN_TARGET} Preview"
    echo "           Alias:    ${USER_ALIAS}"
    echo "          Labels:    ${USER_LABELS}"
    echo "        UserName:    ${USER_NAME}"
    echo "        Password:    ${USER_PASSWORD}"
    echo "            Host:    ${USER_HOST}"
    echo "            Port:    ${USER_PORT}"
    exit 0
}

cmd_health() {
    local dependence_path
    local exit_code=0
    for dependence_bin in ${DEPENDENCE_BINS[*]}; do
        if dependence_path=$(which "${dependence_bin}"); then
            echo -e "${dependence_bin} \t\t is found. path:${dependence_path}"
        else
            echo -e "${dependence_bin} \t\t is not found."
            exit_code=1
        fi
    done

    if [[ $exit_code -eq 0 ]]; then
        echo "All dependences are found."
    else
        echo "Some dependences are not found."
    fi

    exit $exit_code
}

main() {
    local optstring=":P:p:u:i:l:c:a:m:t:dvhr"
    OPTIND=0
    SSH_AGENT=$SSH_AGENT_OPENSSH
    while getopts $optstring opt "$@"; do
        case $opt in
        'd')
            PASSWORD_APPEND_SUFFIX=0
            ;;
        'p')
            USER_PASSWORD="$OPTARG"
            ;;
        'u')
            USER_NAME="$OPTARG"
            ;;
        'v')
            LOGIN_VERBOSE=1
            ;;
        'i')
            USER_HOST="$OPTARG"
            ;;
        'c')
            HOST_RECORD_CONFIG="$OPTARG"
            HOST_RECORD_CONFIG_TEMP="${HOST_RECORD_CONFIG}.temp"
            ;;
        'r')
            SSH_AGENT=$SSH_AGENT_SSHRC
            ;;
        'P')
            USER_PORT="$OPTARG"
            ;;
        'l')
            USER_LABELS="$OPTARG"
            ;;
        'a')
            USER_ALIAS="$OPTARG"
            ;;
        'm')
            RUN_MODE="$OPTARG"
            ;;
        't')
            LOGIN_TARGET="$OPTARG"
            ;;
        ':') ;;
        '?' | 'h')
            cmd_help
            ;;
        esac
    done

    case $RUN_MODE in
    "login")
        cmd_login
        ;;
    "preview")
        cmd_preview
        ;;
    "health")
        cmd_health
        ;;
    *)
        cmd_help
        ;;
    esac

    return $?
}

main "$@"
