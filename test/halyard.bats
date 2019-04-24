#!/usr/bin/env bats

load test_helper

@test "display logo" {
  run cat "${HALYARD_PATH}"/images/logo
  [ "$status" -eq 0 ]
}

@test "halyard executed without args" {
  run halyard
  [ "$status" -eq 1 ]
  [ $(expr "${lines[0]}" : "usage:") -ne 0 ]
}

@test "init creates \`yard\` directory" {
  run halyard init
  [ "$status" -eq 0 ]
  [ -d "yard" ]
  rm -R "yard"
}

@test "load called with directory" {
  run halyard load testfiles
  [ "$status" -eq 0 ]
  [ -f "${CONTAINER_PATH}"/test.cpp ]
  [ -f "${CONTAINER_PATH}"/test.hpp ]
  [ -f "${CONTAINER_PATH}"/.paths ]
}

@test "load called with single file" {
  run halyard load testfiles/test.cpp
  [ "$status" -eq 0 ]
  [ -f "${CONTAINER_PATH}"/test.cpp ]
  [ -f "${CONTAINER_PATH}"/.paths ]
}

@test "load called with multiple files" {
  run halyard load testfiles/test.cpp testfiles/test.hpp
  [ "$status" -eq 0 ]
  [ -f "${CONTAINER_PATH}"/test.cpp ]
  [ -f "${CONTAINER_PATH}"/test.hpp ]
  [ -f "${CONTAINER_PATH}"/.paths ]
}

@test "peek called on loaded container" {
  run halyard load testfiles
  run halyard peek
  [ "$status" -eq 0 ]
}

@test "unload called on loaded container" {
  run halyard load testfiles
  run halyard unload
  [ ! -f "${CONTAINER_PATH}"/test.cpp ]
  [ ! -f "${CONTAINER_PATH}"/test.hpp ]
  [ ! -f "${CONTAINER_PATH}"/.paths ]
  [ "$status" -eq 0 ]
}

@test "reload called on loaded container" {
  run halyard load testfiles
  run halyard reload
  [ "$status" -eq 0 ]
}

@test "run called on loaded container" {
  run halyard load testfiles
  run halyard run
  [ "$status" -eq 0 ]
}

@test "load called without args: usage displayed and exit status 1" {
  run halyard load
  [ "$status" -eq 1 ]
  [ $(expr "${lines[0]}" : "usage:") -ne 0 ]
}

@test "peek called on empty container: exit status 1" {
  run halyard peek
  [ "$status" -eq 1 ]
}

@test "unload called on empty container: exit status 1" {
  run halyard unload
  [ "$status" -eq 1 ]
}

@test "reload called on empty container: exit status 1" {
  run halyard reload
  [ "$status" -eq 1 ]
}

@test "run called on empty container: exit status 1" {
  run halyard run
  [ "$status" -eq 1 ]
}
