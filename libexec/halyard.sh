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

# Load (via rsync) the currenty directory's files into toplevel
# container.
load_container() {
  local files=("$@")
  local file_array=()

  for file in "${files[@]}"; do
    if [[ ! -f "${file}" ]] && [[ ! -d "${file}" ]]; then
      printf "\n${HALYARD_SAYS_NO} ${file} does not exist\n\n"
      exit 1
    fi
    rsync -a "${file}" "${CONTAINER_PATH}"
    file_array+=("${file}")
  done
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
  local target=()
  local target_location=()

  if [[ "${#args[@]}" -eq 0 ]]; then
    echo "usage: halyard load [<dir> | <file> | <file 1> ... <file n>]"
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
    target+=("${file_path}")
    save_file_paths_as_metadata "${file_path}"
  done

  # Copy this directory's files into container.
  load_container "${target[@]}"
  popd >/dev/null 2>&1 || true

  # Everything went well, mark status as loaded
  STATUS="LOADED"

  cat "${HALYARD_PATH}/images/logo"
  display "${target[@]}"
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

  local path_array=()
  while read path; do
    path_array+=("${path}")
  done < "${CONTAINER_PATH}"/.paths

  load_container "${path_array[@]}"

  STATUS="LOADED"
  display "${path_array[@]}"
}

run() {
  docker_start

  # Array for source files.
  local target=()
  local extension
  local compiler
  local file_count=0
  local make_detected=false

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
  if ls "${CONTAINER_PATH}" | grep -iq "makefile"; then
    make_detected=true
    ((file_count = file_count + 1))
  fi

  # No need to `run` on zero files.
  if [[ ! "$file_count" -gt 0 ]]; then
    printf "\n${HALYARD_SAYS_NO} \`run\` called on an empty vessel...\n"
    printf "${HALYARD_SAYS} try to \`load\` before the next \`run\`...\n\n"
    exit 1
  fi

  pushd $CONTAINER_PATH >/dev/null 2>&1
  docker_run "${make_detected}" "${target[@]}"
  rm memcheck
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
  local run_with_make="$1"
  local files=("${@:2}")

  # TODO: Redirect output, parse, and display for user
  # Runs a full leak check and displays results
  if [ "$run_with_make" = true ]; then
    printf "\n${HALYARD_SAYS} makefile detected\n"
    printf "${HALYARD_SAYS} executable path: "; read exec_path; printf "\n"
    docker run --rm -ti -v $PWD:/test halyard:0.1 bash -c \
      "cd /test/; 
       echo 'making ${exec_path}... ';
       make && valgrind --leak-check=full ./${exec_path}"
  else
    docker run --rm -ti -v $PWD:/test halyard:0.1 bash -c \
      "cd /test/; 
       $compiler -o memcheck ${files[*]} &&
       valgrind --leak-check=full ./memcheck"
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
