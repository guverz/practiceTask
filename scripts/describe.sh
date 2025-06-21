#!/usr/bin/env bash

VERSION="0.4"
# use commit number as relase: 0 - do not use (default relase number is 1), 1 - use commite number as release number
RELEASE=0

# versioniong strategy: tag, abbrev, rank
VERSIONING=tag

#    Задание версии пакета, правила
#        1. версия пакета должна совпадать с версией установленного модуля, файла.
#           module -v - должен выдавать ту же версию что и в rpm пакете
#           file-name-version - или файл должен содержать в имени версию совпадающую с rpm
#        2. комментарий должен содержать версию (исключение для версий нумеруeмых через номер коммита), но в этом
#           случае должен совпадать префикс
#    Отсюда несколько стратегий задания версии
#        1. вручную через tag, при этом версию модуля нужно тоже обновлять когда таг добавлять
#        2. автоматически получение номера версии из git и добавление его к модулю при сборке
#
#    По сути две стратегии:
#        - tag - имя берется от последнего тега - для head
#        - commit - это автоматически 
#
#    Но есть одно но, почему я для commit не использую git --abbrev=2 например, когда делаешь мерж ветки в которой был 
#    добавлен тэг ниже по версии в ветку в которой тег старше по версии но изменения сделаны позже git выставляет
#    тег меньшей версии, он же позже поставлен, а то что версия уже ушла не учитывается. В общем мне не нравится алгоритм
#    который использует git, поэтому я сам высчитываю rank и потом получаю версию. 

set -o nounset
set -o errexit

function help {
   echo -e "describe project version and release from git describe"
   echo -e "usage: decribe [-h|--help] [-v|--version] [-r|--release] project|version|release|full"
   echo -e "options:"
   echo -e "    -h|--help      print this help and exit"
   echo -e "    -v|--verbose   print script version and exit"  
   echo -e "    -V|--version   print version number"  
   echo -e "    -d|--debug     debug output"  
   echo -e "    --no-color     no color output"
   echo -e "    -r|--release   use commit number as release number, default is no and relase is 1"
   echo -e "commands:"
   echo -e "    project        print project name"
   echo -e "    version        print projecet version"  
   echo -e "    release        print project release"
   echo -e "    full           print full project name-version-release"
}

########################################################################################################################
# Setup colors

function setup_colors {
    if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
        clre="\e[0m" black='\e[30m' red='\e[31m' green='\e[32m' yellow='\e[33m' blue='\e[34m' magenta='\e[35m' 
        cyan='\e[36m' gray='\e[37m' white='\e[38m' bold='\e[1m' blink='\e[5m]'
    else
        clre='' red='' green='' orange='' blue='' purple='' cyan='' yellow='' bold='' blink=''
    fi
}

########################################################################################################################
# Logging functions

lg() {
    echo -e "${1-}"
}

le() {
    echo >&2 -e "${red}${bold}ERROR${clre}${red}: ${1-}${clre}"
}

lw() {
    echo -e "${purple}WARNING: ${1-}${clre}"
}

ld() {
    if [[ ! -z "${DEBUG-}" && "${DEBUG-}" -gt 0 ]]; then
        echo -e "${yellow}${bold}#DEBUG${clre}${yellow}: ${1-}${clre}"
    fi
}

########################################################################################################################


function git_rank {
    local i=0
    for tag in $(git describe --match "v[0-9]*" --abbrev=0 --always --tags $(git log --pretty=oneline | awk '{print $1}')); do 
        echo "${tag}-${i}"
        ((i++))
    done
}

function git_describe {
    local _version=$(git describe --match "v[0-9]*" --abbrev=0 --always --tags $(git log --pretty=oneline | awk '{print $1}') | sort -rV | head -1 | sed -r 's/-[0-9]+\-g[a-f0-9]+$//')
    git_rank | grep "${_version}-" | sort -rV | head -1
}

function release_suffix {
    local suffix_zero="${1-none}"
    if [[ ${RELEASE} -eq 1 ]]; then
       echo ${_version} | sed -e 's/^v//' | awk -F '-' '{if (NF > 1) print $1; else print $1;}'
       return 0
    fi
    if [[ "${suffix_zero}" == "none" ]]; then
        echo ${_version} | sed -e 's/^v//' | awk -F '-' '{if (NF > 1) print $1"-"$2; else print $1;}'
    else
        echo ${_version} | sed -e 's/^v//' | awk -F '-' '{if (NF > 1) print $1"-"$2; else print $1"-0";}'
    fi
}

function version_tag {
    local _version=$(git describe --match 'v[0-9]*' --abbrev=0 --tags HEAD | sed -e 's/^v//' | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+)\-/\1\~/')
    echo ${_version}
}

function version_abbrev {
   local _version=$(git describe --match "v[0-9]*" --abbrev=2 --always --tags $(git log --pretty=oneline | awk '{print $1}') | sort -rV | head -1 | sed -r 's/\-g[a-f0-9]+$//')
   release_suffix 'zero_padding'
}

function version_rank {
   local _version=$(git_describe)
   release_suffix 'zero_padding'
}

function version {
    case "${VERSIONING-tag}" in
        tag)
            version_tag ;;
        abbrev)
            version_abbrev ;;
        rank)
            version_rank ;;
        *)
            echo -e "unknown versioning strategy ${VERSIONING}"
            exit 1  
    esac
    exit 0
}

function project {
   git remote -v | grep fetch | awk '{print $2}' | awk -F ':' '{print $2}' | sed 's/\//\-/g' | sed 's/.git//'
#    echo ClearingManager-mts
}

function release {
   if [[ ${RELEASE} -eq 1 ]]; then
       git describe --match "v[0-9]*" --abbrev=2 --tags HEAD | sed -r 's/\-g[a-f0-9]+$//' | awk -F '-' '{if (NF > 1) print $NF; else print 0;}'
       return 0
   fi
   echo 1
}

setup_colors

while :; do
    case "${1-}" in
        -h|--help)
           help
           exit 0
           ;;
        -v|--verbose)
           set -x
           ;;
        -d|--debug)
           DEBUG=1
           ;;
        --no-color)
           NO_COLOR=1
           setup_colors
           ;;
        -V)
           echo $VERSION
           exit 0
           ;;
        -r|--release)
           RELEASE=1
           ;;
        version)
           version
           exit 0
           ;;
        project)
           project
           exit 0
           ;;
        release)
           release
           exit 0
           ;;
        full)
           echo $(project)-$(version)-$(release)
           exit 0
           ;;
        -?*)
           le "unknown option: ${1-}"
           ;;
        *)
           le "wrong options: usage: describe project|version|release|full"
           break ;;
    esac
    shift
done
exit 1
