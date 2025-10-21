#!/usr/bin/env bash

help_page () {
    echo 'make';
}

# 解析命令行参数
command="$1";
shift;
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            help_page;
            exit 0;
        ;;
        *)
            formula_or_cask_name="$1"
            shift
            break;
        ;;
    esac
done

if [ -z "${formula_or_cask_name}" ]; then
    echo "formula or cask name unset !";
    exit 1;
fi

# commit and push
publish() {
    git add .
}

audit() {
    brew audit --new --fix "witt/taphup/${formula_or_cask_name}"
}

livecheck() {
    brew livecheck --debug "witt/taphup/${formula_or_cask_name}"
}

${command}