#!/bin/bash

ROOT_PATH=./k8s

function run_kustomize() {
  echo -n "Running kustomize in ${1} ... "
  out=$(cd "${1}" && kustomize build 2>&1)
  if [ $? -ne 0 ]; then
    echo FAILED
    echo "${out}"
    return 1
  else
    echo OK
    return 0
  fi
}

failed=0
for k in $(find ${ROOT_PATH} -iname kustomization.yaml -exec dirname {} \;); do
  run_kustomize "${k}"
  if [ $? != 0 ]; then
    failed=1;
  fi
done

if [ $failed -eq 1 ]; then
  exit 1
fi
