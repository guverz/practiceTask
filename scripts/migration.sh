#!/usr/bin/env bash

VERSION="0.3"
MIGRATION_DIR="migrations";
DEBUG=0
NO_COLOR=

set -o nounset

trap cleanup SIGINT SIGTERM ERR EXIT
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
script_name=$(basename $(readlink -e "${BASH_SOURCE[0]}"))
pid_file=
work_dir=$(pwd -P)

########################################################################################################################
# Parse command line arguments

parse_cmdargs() {
    # default values of variables set from params
    flag=0
    param=''

    while :; do
        ld "arg ${1-}"
        case "${1-}" in
            -h | --help)
                help ;;
            -v | --verbose)
                set -x ;;
            -d | --debug)
                DEBUG=1 ;;
            -V | --version)
                version ;;
            --no-color)
                NO_COLOR=1 ;;
            -?*)
                die "Unknown option: $1" ;;
            *)
                break ;;
        esac
            shift
    done

    args=("$@")

    if [[ ${#args[@]} -eq 0 ]]; then
        help
    fi


    return 0
}

########################################################################################################################
# help
function help {
    lg "migration helper to create migrations scripts"
    lg "usage: migration [-h|--help] [-v|--version] add"
    lg "options:"
    lg "    -h|--help      print this help and exit"
    lg "    -v|--version   print script version and exit"
    lg "commands:"
    lg "    add            add new migrations script with properly defined name"
    lg "    collect        collect migrations on submodules between commits into migrations catalog"
    lg "    check          check unregtistered migrations files at submodules"
    exit 1
}


########################################################################################################################
# Version
version() {
    echo $VERSION
    exit 0
}

########################################################################################################################
# Cleanup, called at any signal SIGINT SIGTERM ERR EXIT, you could extend it or write you own handlers
cleanup() {
    # restore default trap handler
    trap - SIGINT SIGTERM ERR EXIT
    # restore work directory is script is changed it while executing
    cd ${work_dir}
    # you script cleanup here

}

########################################################################################################################
# if terminal is support colors set color variable by color escape sequences

setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    clre='\033[0m' red='\033[0;31m' green='\033[0;32m' orange='\033[0;33m' blue='\033[0;34m' purple='\033[0;35m'
    cyan='\033[0;36m' yellow='\033[1;33m' bold='\e[1m' blink='\e[5m' under='\e[4m' gray='\e[37m'
  else
    clre='' red='' green='' orange='' blue='' purple='' cyan='' yellow='' bold='' blink='' under='' gray=''
  fi
}

########################################################################################################################
# Output colorer functions

ok() {
    printf " ${green}${bold}ok${clre} ${1-}"
}

failed() {
    printf " ${red}${bold}failed${clre} ${1-}"
}

warning() {
    printf " ${purple}${1-}${clre}"
}

error() {
    printf "${red}${bold}${1-}${clre}"
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
    if [[ ! -z "${DEBUG}" && "${DEBUG}" -gt 0 ]]; then
        echo -e "${yellow}${bold}#DEBUG${clre}${yellow}: ${1-}${clre}"
    fi
}

########################################################################################################################
# Die

die() {
    le "$1"
    exit "${2-1}"
}

########################################################################################################################
# split string separated by term default ;
function split {
    local arg_name=${1}
    local arg_term=${2-;}
    IFS=${arg_term} read -ra $arg_name <<< $(cat -)
    if [[ "${!arg_name[0]-}" =~ (ERROR:.*) ]]; then
        echo -e "${red}${BASH_REMATCH[0]}${clre}"
        return 1
    fi
    return 0
}

########################################################################################################################
# parse sql files, search includes
function parse_include {
    local includes_name=${1}
    declare -n includes=${1}
    local file=${2}
    ld "parse file on includes ${file}"
    if [[ ! -f ${file} ]]; then
        die "  include file ${file} does not exists"
    fi
    local file_dir=$(dirname ${file})

    set +o nounset
    size=${#included[@]}
    if [[ ${size} -lt 1 ]]; then
        declare -A included
    fi
    set -o nounset

    while read -r include; do
        ld "  $file include ${include} dir ${file_dir}"
        if [[ ${include} =~ ^@([^\;]+?) ]]; then
            include_file=${BASH_REMATCH[1]}
            ld "  include file ${include_file}"
            #FIXME write meta
            ld "check includes in included"
            if [[ ${included[${include_file}]+_} && "${file}" != "${included[${include_file}]}" ]]; then
                die "include loop detected $include_file inluded by $file already included by ${included[${include_file}]}"
            fi
            included[${include_file}]=${file}
            includes[${include_file}]="$file;${file_dir}/${include_file}"
            parse_include ${includes_name} ${file_dir}/${include_file}
            unset included[${include_file}]
        else
            le "  wrong include ${include}"
        fi
    done < <(cat ${file} | grep '^@')
    if [[ ${size} -lt 1 ]]; then
        unset included
    fi

    return 0
}

########################################################################################################################
# migration add new file

function migration_add {
    local no_help=${1-0}
    local project=$(scripts/describe project)
    local version=$(scripts/describe version)
    local release=$(scripts/describe release)

    echo -e "add migration script ${project}-${version}-${release}";
    local last_migration=$(find ${MIGRATION_DIR} | grep ${project}-${version}-${release} | sort -V | tail -1)
    local increment=0
    if [[ -n "${last_migration-}" ]]; then
        last_migration=$(basename ${last_migration} .sql)
        if [[ ! "${last_migration}" =~ ${project}\-${version}\-${release}\-([0-9]+?)\. ]]; then
            echo -e "wrong migration file name '${last_migration}', could not make new one"
            exit 1
        fi
        increment=${BASH_REMATCH[1]}
    fi
    ((increment++))
    local migration_file="${project}-${version}-${release}-${increment}"

    echo "# ${migration_file}.up.sql" > ${MIGRATION_DIR}/${migration_file}.up.sql
    if [[ ${no_help} -eq 0 ]]; then
        echo "${MINI_HELP}" >> ${MIGRATION_DIR}/${migration_file}.up.sql
    fi;

    echo "# ${migration_file}.down.sql" > ${MIGRATION_DIR}/${migration_file}.down.sql
    if [[ ${no_help} -eq 0 ]]; then
        echo "${MINI_HELP}" >> ${MIGRATION_DIR}/${migration_file}.down.sql
    fi;

    echo -e "created migrations files:"
    echo -e "   ${MIGRATION_DIR}/${migration_file}.up.sql"
    echo -e "   ${MIGRATION_DIR}/${migration_file}.down.sql"
}

########################################################################################################################
function migration_list() {
    # decomposition make this function project_migrations
    project=$(scripts/describe.sh project)
    version=$(scripts/describe.sh version)
    release=$(scripts/describe.sh release)

    # declare map key is md5 of original migration script, value is meta
    declare -gA project_migrations
    # declare map, key is file name of original migration script, value is meta
    declare -gA module_migrations

    #FIXME need declare project includes files, and original script files
    declare -gA project_includes
    declare -gA project_md5_includes
    declare -gA deleted_includes
    declare -gA module_includes
    declare -gA missed_includes

    missed_includes_cnt=0
    deleted_includes_cnt=0

    # meta is
    # file prefix;file ext;file path;migration script up;migration script down

    ####################################################################################################################
    # read migrations catalog, for each .up.sql file

    while read -r file; do
        ld "found ${file}"
        local file_name=$(basename ${file})
        local file_dir=$(dirname ${file})

        ################################################################################################################
        # check pair .down.sql exists
        if [[ ! "${file_name}" =~ (.+\-[0-9\.\-]+)\.up\.([^\.]+)$ ]]; then
            #lw "wrong file name '${file_name}' expect at name-x[.y[.z][-r].up.ext"
            continue;
        fi
        local file_prefix=${BASH_REMATCH[1]}
        local file_ext=${BASH_REMATCH[2]}

        local _file_name="${file_prefix}.down.${file_ext}"
        local _file="${file_dir}/${_file_name}"
        if [[ ! -f "${_file}" ]]; then
            die "file ${file_name} do not have counterpart file ${_file_name} at '${file_dir}'"
        fi
        ################################################################################################################

        # get source of original migration file
        local migration_meta=$(cat ${file} | grep '#migration: ' | awk '{print $2}')

        declare -A migration_includes
        declare -A migration_md5_includes
        declare -A original_includes

        parse_include migration_includes ${file}
        parse_include migration_includes ${_file}

        # if meta is defined
        if [[ -n "${migration_meta}" ]]; then

            split data <<< "${migration_meta}"
            local migration_file="${data[0]}"
            local migration_md5="${data[1]-undefined}"

            local migration_name=$(basename ${migration_file})
            local migration_dir=$(dirname ${migration_file})
            if [[ ! "${migration_name}" =~ (.+\-[0-9\.\-]+)\.up\.([^\.]+)$ ]]; then
                die "in file '${file_name}' wrong meta #migration '${parent_migration}' expect at name-x[.y[.z][-r].up.ext"
            fi
            local migration_prefix=${BASH_REMATCH[1]}
            local migration_ext=${BASH_REMATCH[2]}

            local _migration_name="${migration_prefix}.down.${migration_ext}"
            local _migration_file="${migration_dir}/${_migration_name}"
            if [[ ! -f "${_migration_file}" ]]; then

                if [[ ! -f "${migration_file}" ]]; then
                    le "migration ${file_name} does not have based migration file ${migration_file}"
                    # WARNING dangerous operation, check $file is not zero and this is a regular file!
                    if [[ -n "${file}" && -f "${file}" ]]; then
                        le "  delete ${file_name}"
                        rm -f "${file}"
                    fi
                    # WARNING dangerous operation, check $_file is not zero and this is a regular file!
                    if [[ -n "${_file}" && -f "${_file}" ]]; then
                        le "  delete ${_file_name}"
                        rm -f "${_file}"
                    fi
                    continue;
                else
                    die "BUG: file ${migration_name} do not have counterpart file ${_migration_name} at '${migration_dir}'"
                fi
            else
                if [[ ! -f "${migration_file}" ]]; then
                    die "BUG: file ${_migration_name} do not have counterpart file ${migration_name} at '${migration_dir}'"
                fi
            fi

            #local migration_md5="$(md5sum ${migration_file}| awk '{print $1}')$(md5sum ${_migration_file}| awk '{print $1}')"
            ld "${migration_md5};${migration_prefix};${migration_ext};${migration_dir};${migration_name};${_migration_name}"
            project_migrations["${migration_prefix}:${migration_md5}"]="${migration_prefix};${migration_ext};${migration_dir};${migration_name};${_migration_name}"
            module_migrations[${migration_prefix}]="${file_prefix};${file_ext};${file_dir};${file_name};${_file_name}"

            parse_include original_includes ${migration_file}
            parse_include original_includes ${_migration_file}

            # remove MIGRATION_DIR from path, include file has already have it in their names
            original_include_dir=$(dirname ${migration_dir})
            # build md5 includes from migrations includes
            for include_file in ${!migration_includes[@]}; do
                split data <<< "${migration_includes[${include_file}]}"
                local including_file=${data[0]}
                local included_file=${data[1]}
                local file_md5=$(md5sum ${included_file} | awk '{print $1}')
                migration_md5_includes["${included_file}:${file_md5}"]=${included_file}
                project_md5_includes["${included_file}:${file_md5}"]=${included_file}
                ld "md5 ${file_md5} of include file ${included_file} included by ${including_file} and check in original includes at ${original_include_dir}"
                # check file is exists in directory of
                if [[ ! -f "${original_include_dir}/${included_file}" ]]; then
                    #maybe deleted
                    le "include ${include_file} may be deleted from ${original_include_dir}/${included_file}, check later"
                    deleted_includes[${include_file}]="${included_file}"
                    ((deleted_includes_cnt++))
                fi

            done

            # compare includes and fill missed_includes or deleted includes
            for include_file in ${!original_includes[@]}; do
                split data <<< "${original_includes[${include_file}]}"
                local including_file=${data[0]}
                local included_file=${data[1]}
                local file_md5=$(md5sum ${included_file} | awk '{print $1}')
                included_relative_file=$(echo ${included_file} | cut -d'/' -f2-)
                ld "md5 ${file_md5} of include file ${included_file} included by ${including_file} and check in migration_includes"
                if [[ ! ${migration_md5_includes["$included_relative_file:${file_md5}"]+_} ]]; then
                    if [[ ! ${missed_includes[${included_file}]+_} ]]; then
                        lw "include file ${included_file} is changed or not exists in migration includes"
                        missed_includes[${included_file}]="${including_file};${included_file};";
                        ((missed_includes_cnt++))
                    fi
                fi

                module_includes[${include_file}]="${including_file};${included_file};"

            done

        else
        # if meta is undefined, migration file is original file
            local file_md5="$(md5sum ${file} | awk '{print $1}')$(md5sum ${_file}| awk '{print $1}')"
            project_migrations["${file_prefix}:${file_md5}"]="${file_prefix};${file_ext};${file_dir};${file_name};${_file_name}"
            ld "${file_md5};${file_prefix};${file_ext};${file_dir};${file_name};${_file_name}"

            for include_file in ${!migration_includes[@]}; do
                split data <<< "${migration_includes[${include_file}]}"
                local including_file=${data[0]}
                local included_file=${data[1]}
                project_includes[${include_file}]="${including_file};${included_file}"
            done
        fi

        unset migration_includes
        unset migration_md5_includes
        unset original_includes

    done < <(find ${MIGRATION_DIR} -type f | grep -v '\.down\.' | grep -v 'README.md' | grep -v "\.txt" | sort -V)

    ####################################################################################################################
    # list submodules migrations to find uncollected or changed files

    missed_files=0

    # map for missed or changed files, key is file name of migration script, value is meta
    declare -gA missed_migrations
    # meta:
    # file prefix; file ext; file path; migration script up; original script down

    # for each git submodule
    while read -r submodule; do

        # if submodule has migration directory
        if [[ -d  "${submodule}/${MIGRATION_DIR}" ]]; then
            local submodule_project
            if [[ -e ${submodule}/describe ]]; then
                submodule_project=$(cd ${submodule} && ./describe.sh project)
            elif [[ -e ${submodule}/scripts/describe ]]; then
                submodule_project=$(cd ${submodule} && ./scripts/describe.sh project)
            else
                le "submodule ${submodule} has no describe script"
                continue
            fi
            ld "submodule project ${submodule_project}"

            # for each file in submodule migrations directory
            while read -r file; do

                local file_name=$(basename ${file})
                local file_dir=$(dirname ${file})
                ld "file ${file} name $file_name dir ${file_dir}"
                if [[ ! "${file_name}" =~ (.+\-[0-9\.-]+)\.up\.([^\.]+)$ ]]; then
                    #lw "wrong file name '${file_name}' expect at x[.y[.z][-r].up.ext the end"
                    continue;
                fi
                local file_prefix=${BASH_REMATCH[1]}
                local file_ext=${BASH_REMATCH[2]}

                local _file_name="${file_prefix}.down.${file_ext}"
                local _file="${file_dir}/${_file_name}"
                if [[ ! -f "${_file}" ]]; then
                    die "file ${file_name} do not have counterpart file ${_file_name} at '${file_dir}'"
                fi

                if [[ ! "$file_name" =~ ^${submodule_project} ]]; then
                    ld "\tfile not started with project name '${submodule_project}'"
                    file_name="${submodule_project}-${file_name}"
                fi
                #check file name contain project and submodule name, if not add
                local file_md5="$(md5sum ${file}| awk '{print $1}')$(md5sum ${_file}| awk '{print $1}')"
                ld "${file_md5};${file_prefix};${file_ext};${file_dir};${file_name};${_file_name}"

                # compare script md5, if it is changed than add into missed migration
                if [[ ! ${project_migrations["${file_prefix}:${file_md5}"]+_} ]]; then
                    missed_migrations[${missed_files}]="${file_prefix};${file_ext};${file_dir};${file_name};${_file_name}"
                    ((missed_files++))
                fi

            done < <(find ${submodule}/${MIGRATION_DIR} -type f | grep -v '\.down\.' | sort -V)
        fi
    done < <(git submodule | awk '{print $2}')
}

########################################################################################################################
# migration collect

function migration_collect() {
    # local start_time=$(date +%s%3N)
    local collected=0
    migration_list
    if [[ ${missed_files} -gt 0 ]]; then
        lg "there is unregistered migration files pairs (${missed_files}), collect:"
        local i=0;
        for ((i=0; i < ${#missed_migrations[@]}; i++)); do
            split data <<< "${missed_migrations[$i]}"
            local file_prefix=${data[0]}
            local file_ext=${data[1]}
            local file_dir=${data[2]}
            local file_name_up=${data[3]}
            local file_name_down=${data[4]}

            if [[ ! -f "${file_dir}/${file_name_up}" ]]; then
                le "BUG: there is no file ${file_dir}/${file_name_up}, something wrong"
                exit 1
            fi
            if [[ ! -f "${file_dir}/${file_name_down}" ]]; then
                le "BUG: there is no file ${file_dir}/${file_name_down}, something wrong"
                exit 1
            fi

            # before check name exists in module_migrations file_prefix=>project_migration_file_pair
            if [[ -n "${module_migrations[${file_prefix}]+_}" ]]; then
                # update old migration file
                split data <<< "${module_migrations[${file_prefix}]}"
                local migration_prefix=${data[0]}
                local migration_ext=${data[1]}
                local migration_dir=${data[2]}
                local migration_name_up=${data[3]}
                local migration_name_down=${data[4]}
                if [[ ! -f "${migration_dir}/${migration_name_up}" ]]; then
                   die "BUG: there is no file ${migration_dir}/${migration_name_up}, something wrong"
                fi
                if [[ ! -f "${migration_dir}/${migration_name_down}" ]]; then
                    die "BUG: there is no file ${migration_dir}/${migration_name_down}, something wrong"
                fi
                head -1 ${migration_dir}/${migration_name_up} > ${migration_dir}/${migration_name_up}
                head -1 ${migration_dir}/${migration_name_down} > ${migration_dir}/${migration_name_down}
                lw "    pair ${file_prefix}.{up,down}.${file_ext} update migration ${migration_prefix}.{up,down}.${migration_ext}"
            else
                # migration add without help, but fucking check that inludes is exists
                # ye i'm not polite with the eglish language
                declare -A original_includes
                parse_include original_includes "${file_dir}/${file_name_up}"
                parse_include original_includes "${file_dir}/${file_name_down}"

                migration_add 1
                local last_migration=$(find ${MIGRATION_DIR} | grep ${project}-${version} | sort -V | tail -1)
                local migration_name=$(basename ${last_migration})
                local migration_dir=$(dirname ${last_migration})
                if [[ ! "${migration_name}" =~ (.+\-[0-9\.-]+)\.up\.([^\.]+)$ ]]; then
                    die "wrong file name '${migration_name}' expect  name-x[.y[.z][-r].up.ext"
                fi
                local migration_prefix=${BASH_REMATCH[1]}
                local migration_ext=${BASH_REMATCH[2]}
                local migration_name_up="${migration_prefix}.up.${migration_ext}"
                local migration_name_down="${migration_prefix}.down.${migration_ext}"
                if [[ ! -f "${migration_dir}/${migration_name_up}" ]]; then
                   die "BUG: there is no file ${migration_dir}/${migration_name_up}, something wrong"
                fi
                if [[ ! -f "${migration_dir}/${migration_name_down}" ]]; then
                    die "BUG: there is no file ${migration_dir}/${migration_name_down}, something wrong"
                fi


                # compare includes and fill missed_includes or deleted includes
                for include_file in ${!original_includes[@]}; do
                    ld "include file $include_file"
                    split data <<< "${original_includes[${include_file}]}"
                    local including_file=${data[0]}
                    local included_file=${data[1]}
                    local file_md5=$(md5sum "${included_file}" | awk '{print $1}')
                    included_relative_file=$(echo "${included_file}" | cut -d'/' -f2-)
                    ld "md5 ${file_md5} of include file ${included_file} included by ${including_file} and check in migration_includes"
                    if [[ ! ${project_md5_includes["$included_relative_file:${file_md5}"]+_} ]]; then
                        if [[ ! ${missed_includes[${included_file}]+_} ]]; then
                            ld "include file ${included_file} is changed or not exists in migration includes"
                            missed_includes[${included_file}]="${including_file};${included_file};"
                            ((missed_includes_cnt++))
                        fi
                    fi
                done

                unset original_includes

                lg "    pair ${file_prefix}.{up,down}.${file_ext} save migration: ${migration_prefix}.{up,down}.${migration_ext}"
            fi
            local file_md5="$(md5sum ${file_dir}/${file_name_up} | awk '{print $1}')$(md5sum ${file_dir}/${file_name_down} | awk '{print $1}')"
            echo -e "#migration: ${file_dir}/${file_name_up};${file_md5}" >> "${migration_dir}/${migration_name_up}"
            cat "${file_dir}/${file_name_up}" >> "${migration_dir}/${migration_name_up}"
            echo -e "#migration: ${file_dir}/${file_name_down};${file_md5}" >> "${migration_dir}/${migration_name_down}"
            cat "${file_dir}/${file_name_down}" >> "${migration_dir}/${migration_name_down}"
            ((collected++))
            ((collected++))
        done
    fi

    if [[ ${missed_includes_cnt} -gt 0 ]]; then
        lg "there is missed includes ${#missed_includes[@]}"
        for include_file in ${!missed_includes[@]}; do
            ld "include file ${include_file}"

            #get its md5
            split data <<< "${missed_includes[${include_file}]}"
            local including_file=${data[0]}
            local included_file=${data[1]}
            local file_md5=$(md5sum ${included_file} | awk '{print $1}')
            #make relative
            local included_relative_file=$(echo ${included_file} | cut -d'/' -f2-)
            ld "md5 ${file_md5} of include file ${included_file} included by ${including_file} and check in project_includes"
            local included_relative_path=$(dirname $included_relative_file)
            if [[ ! -d "${included_relative_path}" ]]; then
                mkdir -p "${included_relative_path}"
                if [[ ! -d "${included_relative_path}" ]]; then
                    die "failed create directory for include files ${included_relative_path}"
                fi
            fi
            #check if it exists in project_modules
            if [[ ${project_includes[${included_relative_file}]+_} ]]; then
                #check if it was changed
                local migration_md5=$(md5sum ${included_file} | awk '{print $1}')
                if [[ "${file_md5}" != "${migration_md5}" ]]; then
                    lw "${included_relative_file} there is in project includes ${included_relative_file}, it was changed, replace it"
                    cp -f "${included_file}" "${included_relative_file}"
                    if [[ $? -gt 0 ]]; then
                        die "failed copy ${included_file} to ${included_relative_file}"
                    fi
                    ((collected++))
                fi
            else
                # if not exists add !
                lg "    add include file ${included_file}"
                cp "${included_file}" "${included_relative_file}"
                if [[ $? -gt 0 ]]; then
                    die "failed copy ${included_file} to ${included_relative_file}"
                fi
                project_includes[${included_relative_file}]=${included_file}
                ((collected++))
            fi

        done
    fi

    if [[ ${deleted_includes_cnt} -gt 0 ]]; then
        ld "there is deleted includes ${#deleted_includes[@]}"
        for include_file in ${!deleted_includes[@]}; do
            local included_file=${deleted_includes[${include_file}]}
            lg "include file ${include_file} $included_file"
            #check file exists in project_includes, i.e inlcuded by some one else, then do not delete
            if [[ ! ${project_includes[${included_file}]+_} && ! ${module_includes[${included_file}]+_} ]]; then
                #WARNING!!! dangerous operation, check before delete
                if [[ -n "${included_file}" && -f "${included_file}" ]]; then
                    le "delete include $included_file"
                    rm -f "${included_file}"
                    if [[ $? -gt 0 ]]; then
                        die "failed delete ${included_file}"
                    fi
                    ((collected++))
                fi
            fi
        done
    fi

    migration_validation


    # local end_time=$(date +%s%3N)
    # local elapsed=$((end_time - start_time))
    # lg "Время выполнения: ${elapsed} мс"

    if [[ ${collected} -gt 0 ]]; then
        lg "${green}[ok]${clre} collected ${collected} file(s)"
    else
        lg "${green}[ok]${clre} nothing to collect"
    fi
    exit 0
}

########################################################################################################################
# migration check

function migration_check() {
    # local start_time=$(date +%s%3N)
    migration_list
    if [[ ${missed_files} -gt 0 ]]; then
        le "there is unregistered migration files pairs (${missed_files}), collect them and commit:"
        for file_md5 in ${!missed_migrations[@]}; do
            split data <<< "${missed_migrations[${file_md5}]}"
            lg "\t${data[0]}.{up,down}.${data[1]}"
        done
        lg "do: scripts/migration collect"
        exit 1
    fi
    migration_validation
    # local end_time=$(date +%s%3N)
    # local elapsed=$((end_time - start_time))
    # lg "Время выполнения: ${elapsed} мс"
    exit 0
}

########################################################################################################################
# migration validation
function migration_validation() {
    declare -A migrations
    declare -A migration_includes
    while read -r file; do
        ld "found ${file}"
        file_name=$(basename ${file})
        file_md5=$(md5sum ${file}| awk '{print $1}')
        migrations[${file_name}]="$file_name;$file"
        if [[ "${file_name}" =~ (.+)\.(up|down)\.sql$ ]]; then
            parse_include migration_includes "${file}"
        fi
        #FIXME check its name if it hash properly name, parse includes
    done < <(find ${MIGRATION_DIR} -type f | grep -v 'README.md' | grep -v "\.txt" | sort -V)
    local -i wrong_files=0
    #FIXME check if file is in included list then file is correct
    for file_name in ${!migrations[@]}; do
        split data <<< "${migrations[${file_name}]}"
        local file=${data[1]}
        relative_file=$(echo ${file} | cut -d'/' -f2-)
        ld "file ${file_name} check name is correct $file"
        if [[ ! "${file_name}" =~ (.+)\.(up|down)\.sql$ ]]; then
            if [[ ! ${migration_includes[${relative_file}]+_} ]]; then
                le "${file_name} wrong file name suffix expect .up.sql or .down.sql"
                ((wrong_files++))
                continue;
            fi
            continue;
        fi
        local prefix=${BASH_REMATCH[1]}
        local suffix=${BASH_REMATCH[2]}
        local _file_name=
        if [[ "$suffix" == "up" ]]; then
            _file_name="${prefix}.down.sql"
        else
            _file_name="${prefix}.up.sql";
        fi
        ld "file ${file_name} check counterpart ${_file_name} exists"
        if [[ ! ${migrations[${_file_name}]+_} ]]; then
            le "${file_name} counterpart as ${_file_name} not found"
            ((wrong_files++))
        fi
    done
    if [[ ${wrong_files} -gt 0 ]]; then
        die "there is wrong files ${wrong_files}, fix them"
    fi
}


########################################################################################################################
# mini help variable contains template text included in each migrations scripts
MINI_HELP=$(cat <<EOF
################################################################################
## !!! Don't forget connect to database source, uncomment:
#connect source
## Source may be a source name from configuration file
## Or it a connect string in format:
#connect Driver://user:password@host[:port]/dbname
################################################################################
## Requests must be separated by ';' delimeter
#select sysdate from dual;
################################################################################
## Use '/' for delimeter PL/SQL code, begin end or create functions, procedures,
## Packages and any other object that contain PL/SQL code, exmaple
#begin
#   -- any pl/sql code
#end;
#/
################################################################################
## Script could include another file with sql:
#@include.sql
## !!! Avoid include migration scripts
################################################################################
## To continue or break on specific errors use:
#whenever error [pattern] continue|break
################################################################################
## Additional help
## roam-sql -h|--help for command line options
## roam-sql -i|--info for syntax help
EOF
)


########################################################################################################################
# main

########################################################################################################################
# setup and parse command line arguments
setup_colors
parse_cmdargs "$@"

case ${args[0]} in
    add)
        migration_add
        exit 0
        ;;
    collect)
        migration_collect
        exit 0
        ;;
    check)
        migration_check
        exit 0
        ;;
    add)
        migration_add
        exit 0
        ;;
    *)
        die "unknown command '${args[0]}'"
esac


exit 1
