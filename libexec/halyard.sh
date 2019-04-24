#!/bin/bash

# Path to the yard.
readonly YARD_DIR_PATH="$PWD/yard/"

# The yard directory stores Valgrind output.
readonly YARD_OUT_PATH="$YARD_DIR_PATH/yard.txt"

# Path to the toplevel halyard directory.
readonly HALYARD_PATH="$HOME/.halyard"

# Path to the toplevel halyard container.
readonly CONTAINER_PATH="$HALYARD_PATH/container"

# Halyard says... something to guide users to functionality.
readonly HALYARD_SAYS="\t\x1b[33mhalyard: \x1b[0m"

# Halyard says no... to invalid operations. (i.e. calling
# peek, unload, or run on an empty vessel/directory.
readonly HALYARD_SAYS_NO="\t\x1b[01;31mhalyard: \x1b[0m"

# Initialize a `yard` directory within the current
# working directory to store Valgrind output to be
# parsed.
# TODO: Ensure users can't init anywhere besides
# their current workspace.
init() {
  if [[ ! -e $YARD_DIR_PATH ]]; then
    mkdir $YARD_DIR_PATH
    printf "\x1b[33m Initialized empty yard in \x1b[0m ${PWD}\n"
  else
    printf "\x1b[33m ${YARD_DIR_PATH} \x1b[0m already exists!\n"
  fi
}

# Resolve the absolute path for a file in the current directory
get_abs_path() {
  echo "$(cd $(dirname "$1"); pwd -P)/$(basename "$1")"
}

# Utility function that formats and display contents of
# an array of collected files (file names).
display() {
  local file_array=("$@")

  local divider=====================================
  local divider=$divider$divider$divider$divider

  local header="\n%-15s %-25s %12s %10s\n"
  local format=""
  local width=67

  if [[ "$STATUS" = "LOADED" ]]; then
    format="\x1b[22;33m%-15s\x1b[0m %-25s \x1b[33m%12s\x1b[0m %10d\n"
  else
    format="%-15s %-25s \x1b[33m%12s\x1b[0m %10d\n"
  fi

  printf "${header}" "STATUS" "FILE_NAME" "FILE_EXTENSION" "FILE_SIZE"
  printf "%$width.${width}s\n" "$divider"

  for file_name in "${file_array[@]}"; do
    local trunc_file_name="${file_name##*/}"
    EXTENSION=$([[ "$trunc_file_name" = *.* ]] && echo ".${trunc_file_name##*.}" || echo '')
    FILESIZE=$(stat -f '%z' "${file_name}")
    printf "$format" "[${STATUS}]" "${trunc_file_name}" "${EXTENSION} " "${FILESIZE}"
  done
  printf "\n"
}

# Write the passed absolute path to container/.paths
# if it is not already there
save_file_paths_as_metadata() {
  local file_path=$1
  local path_exists=false

  while read path; do
    if [[ "${file_path}" = "${path}" ]]; then 
      path_exists=true
    fi
  done < "${CONTAINER_PATH}"/.paths
  if [[ "${path_exists}" = false ]]; then
    echo "${file_path}" >> "${CONTAINER_PATH}"/.paths
  fi
}

# Lists files that are currently loaded in container.
peek() {
  # The number of files in the vessel.
  local file_count=0

  # Array to hold the file names within the vessel.
  local file_array=()

  # Collect file names into `file_array` to be passed
  # to display. Count the number of files on this pass
  # to avoid a call to `display` if the vessel is empty.
  for file in "$CONTAINER_PATH"/*; do
    if [ ${file##*/} != "Dockerfile" ]; then
      file_array+=("${file}")
      ((file_count = file_count + 1))
    fi
  done

  # HACK: [fix me] - there has to be a better solution
  STATUS="LOADED"

  # Only display from peek if the vessel is loaded.
  if [[ "$file_count" -gt 0 ]]; then
    display "${file_array[@]}"
  else
    printf "\n${HALYARD_SAYS_NO} \`peek\` called on an empty vessel...\n"
    printf "${HALYARD_SAYS} try to \`load\` the vessel before the next \`run\`...\n\n"
    exit 1
  fi
}

# Loads this current directory's files into toplevel
# docker container.
load() {
  local args=("$@")
  local loaded_files=()
  local target_location=()

  if [[ "${#args[@]}" -eq 0 ]]; then
    echo "usage: halyard load [<dir> | <file> | <file 1> ... <file n>]"
    exit 1
  elif [[ -f "${CONTAINER_PATH}"/.paths ]]; then
    printf "\n${HALYARD_SAYS_NO} the vessel is already loaded...\n"
    printf "${HALYARD_SAYS} use \`reload\` to update any changes, or \`unload\` to start over\n\n"
    exit 1
  fi

  # Metadata for contained files
  touch "${CONTAINER_PATH}"/.paths

  if [[ -d "${args}" ]]; then
    pushd "${args}" >/dev/null 2>&1
    echo "Preparing contents of ${PWD##*/}..."
    # Since provided target is a dir, set target to its contents
    target_location=("$(pwd)"/*)
  else
    # Otherwise target is all passed args
    target_location=("${args[@]}")
  fi

  # Accumulate the targets and save their paths for reference
  for file in "${target_location[@]}"; do
    local file_path="$(get_abs_path ${file})"
    if [[ ! -f "${file}" ]] && [[ ! -d "${file}" ]]; then
      printf "\n${HALYARD_SAYS_NO} ${file} does not exist\n\n"
      rm "${CONTAINER_PATH}"/.paths
      exit 1
    fi
    # CMakeCache.txt contains information relevant only to build location
    if [[ "${file##*/}" != "CMakeCache.txt" ]]; then
      rsync -a "${file_path}" "${CONTAINER_PATH}"
      loaded_files+=("${file_path}")
      save_file_paths_as_metadata "${file_path}"
    fi
  done

  popd >/dev/null 2>&1 || true

  # Everything went well, mark status as loaded
  STATUS="LOADED"

  cat "${HALYARD_PATH}/images/logo"
  display "${loaded_files[@]}"
}

# Removes files that are currently loaded in container.
unload() {
  # The number of files in the vessel.
  local file_count=0

  # Array to hold the file names within the vessel.
  local file_array=()

  # Collect file names into `file_array` to be passed
  # to display. Count the number of files on this pass
  # to avoid a call to `display` if the vessel is empty.
  for file in "$CONTAINER_PATH"/*; do
    if [ ${file##*/} != "Dockerfile" ]; then
      file_array+=("${file}")
      ((file_count = file_count + 1))
    fi
  done

  # Delete removed files' metadata
  rm "${CONTAINER_PATH}"/.paths >/dev/null 2>&1 || true

  # Only `display` from `unload` if the vessel has been unloaded.
  if [[ "$file_count" -eq 0 ]]; then
    printf "\n${HALYARD_SAYS_NO} \`unload\` called on an empty vessel...\n"
    printf "${HALYARD_SAYS} vessel must be \`load[ed]\` before it can be \`unload[ed]\`...\n\n"
    exit 1
  fi

  # Mark status as unloaded and display the files
  # being unloaded from the vessel.
  STATUS="UNLOADED"
  display "${file_array[@]}"

  for file in "$CONTAINER_PATH"/*; do
    if [ ${file##*/} != "Dockerfile" ]; then
      rm -R "$file"
    fi
  done
}

# Updates files that are currently loaded in container 
# with any changes to their source files
reload() {
  if [[ ! -f "${CONTAINER_PATH}"/.paths ]]; then
    printf "\n${HALYARD_SAYS_NO} \`reload\` called on an empty vessel...\n"
    printf "${HALYARD_SAYS} vessel must be \`load[ed]\` before it can be \`reload[ed]\`...\n\n"
    exit 1
  fi

  local loaded_files=()
  while read metadata; do
    loaded_files+=("${metadata}")
  done < "${CONTAINER_PATH}"/.paths
  
  for file in "${loaded_files[@]}"; do
    # If file changes in any way (name, deleted) it will not successfully load
    if [[ ! -f "${file}" ]] && [[ ! -d "${file}" ]]; then
      printf "\n${HALYARD_SAYS_NO} ${file} does not exist\n\n"
      exit 1
    fi
    # CMakeCache.txt contains information relevant only to build location
    rsync -a "${file}" "${CONTAINER_PATH}"
  done

  STATUS="LOADED"
  display "${loaded_files[@]}"
}

run() {
  docker_start

  # Array for source files.
  local target=()
  local extension
  local compiler
  local make_type
  local file_count=0

  for file in "${CONTAINER_PATH}"/*; do
    extension="${file##*.}"
    # Set compiler based on source extension
    if [ $extension = "c" ] || [ $extension = "cpp" ] || [ $extension = "cc" ]; then
      case $extension in
        "c") compiler="gcc" ;;
        "cpp" | "cc") compiler="g++" ;;
      esac
      target+=("${file##*/}")
      ((file_count = file_count + 1))
    fi
  done

  # Check for makefiles
  if ls "${CONTAINER_PATH}" | grep -iq "CMake"; then
    make_type="cmake"
    ((file_count = file_count + 1))
  elif ls "${CONTAINER_PATH}" | grep -iq "makefile"; then
    make_type="makefile"
    ((file_count = file_count + 1))
  fi

  # No need to `run` on zero files.
  if [[ ! "$file_count" -gt 0 ]]; then
    printf "\n${HALYARD_SAYS_NO} \`run\` called on an empty vessel...\n"
    printf "${HALYARD_SAYS} try to \`load\` before the next \`run\`...\n\n"
    exit 1
  fi

  pushd $CONTAINER_PATH >/dev/null 2>&1
  docker_run "${make_type}" "${target[@]}"
  popd >/dev/null 2>&1
}

# Starts Docker if not already running
docker_start() {
  open --background -a Docker >/dev/null 2>&1 || 
    (printf "\n${HALYARD_SAYS_NO} Docker not found\n\n" && exit 1)

  if ! docker system info >/dev/null 2>&1; then
    echo "Staring Docker..." &&
      while ! docker system info >/dev/null 2>&1; do
        sleep 1
      done
  fi
}

# Runs Memcheck in a Docker container instance
# with the loaded files
docker_run() {
  local make_type="$1"
  local files=("${@:2}")
  local build_path
  local exec_path

  # TODO: Redirect output, parse, and display for user
  # Runs a full leak check and displays results
  if [[ -z "${make_type}" ]]; then
    docker run --rm -ti -v $PWD:/test halyard:0.1 bash -c \
      "cd /test/; 
       $compiler -o memcheck ${files[*]} &&
       valgrind --leak-check=full ./memcheck"
       rm "memcheck" >/dev/null 2>&1 || true
  else
    if [[ "$make_type" = "cmake" ]]; then
      local build_path="."
      printf "\n${HALYARD_SAYS} cmake detected\n"
      printf "${HALYARD_SAYS} out-of-place build? (y/n [n]) "; read input
      if [[ "$input" = "y" ]]; then
        printf "${HALYARD_SAYS} build directory: "; read build_path; printf "\n"
      fi
      printf "${HALYARD_SAYS} executable path: "; read exec_path; printf "\n"
      if [[ -z "${exec_path}" ]]; then
        printf "\n${HALYARD_SAYS_NO} \`run\` executable path must be provided...\n\n"
        exit 1
      fi

      docker run --rm -ti -v $PWD:/test halyard:0.1 bash -c \
        "cd /test/; 
         echo 'making ${exec_path}... ';
         cmake ${build_path};
         make && valgrind --leak-check=full ./${exec_path}"

    elif [[ "$make_type" = "makefile" ]]; then
      printf "\n${HALYARD_SAYS} makefile detected\n"
      printf "${HALYARD_SAYS} executable path: "; read exec_path; printf "\n"
      if [[ -z "${exec_path}" ]]; then
        printf "\n${HALYARD_SAYS_NO} \`run\` executable path must be provided...\n\n"
        exit 1
      fi

      docker run --rm -ti -v $PWD:/test halyard:0.1 bash -c \
        "cd /test/; 
         echo 'making ${exec_path}... ';
         make && valgrind --leak-check=full ./${exec_path}"

    fi
    rm "${CONTAINER_PATH}/${exec_path}" >/dev/null 2>&1 || true
  fi
}

main() {
  set -e

  if [[ "$#" -eq 0 ]]; then
    echo "usage: halyard [options] <command> [<args>]"
    exit 1
  fi

  # Parse optional flags
  # I expect we will have more than this
  while [[ "${1:0:1}" = "-" ]]; do
    # Pass until flags are added.  Will we need any?
    # I'm leaving the infra in place for now in case
    # we decide some options will be needed.
    :
    case "${1:1:1}" in
      "") : ;;
    esac
    shift
  done

  case "$1" in
    "init") init "${@:1}" ;;
    "load") load "${@:2}" ;;
    "run") run "${@:2}" ;;
    "peek") peek ;;
    "unload") unload ;;
    "reload") reload ;;
  esac
}

main "$@"
