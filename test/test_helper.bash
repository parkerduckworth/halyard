#!/usr/bin/env bats

setup() {
  export HALYARD_PATH="${HOME}/.halyard"
  export CONTAINER_PATH="${HALYARD_PATH}/container"
}

teardown() {
  rm -f "${CONTAINER_PATH}"/test.cpp
  rm -f "${CONTAINER_PATH}"/test.hpp
  rm -f "${CONTAINER_PATH}"/.paths
}
