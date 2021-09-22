#!/bin/sh

IMAGESTREAM_NAME='s2i-minimal-notebook-anaconda'
CONFIGMAP_NAME='anaconda-ce-validation-result'

function generate_payload() {
  cat << EOM
---
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: s2i-minimal-notebook-anaconda
  labels:
    opendatahub.io/notebook-image: "false"
    opendatahub.io/modified: "false"
  annotations:
    opendatahub.io/notebook-image-url: "https://github.com/Xaenalt/s2i-minimal-notebook"
    opendatahub.io/notebook-image-name: "Anaconda Commercial Edition"
    opendatahub.io/notebook-image-desc: "Notebook with Anaconda CE tools instead of pip."
spec:
  lookupPolicy:
    local: true
  tags:
  - annotations:
      openshift.io/imported-from: quay.io/modh/s2i-minimal-notebook-anaconda
      opendatahub.io/notebook-software: '[{"name":"Anaconda-Python","version":"v3.8.5"}]'
      opendatahub.io/notebook-python-dependencies: '[{"name":"Anaconda","version":"2020.11"},{"name":"conda","version":"4.9.2"}]'
    from:
      kind: DockerImage
      name: quay.io/modh/s2i-minimal-notebook-anaconda:py38
    name: "py38"
    referencePolicy:
      type: Source
EOM
}

function get_variable() {
  cat "/etc/secret-volume/${1}"
}

function verify_image_exists() {
  if ! oc get imagestream "${IMAGESTREAM_NAME}" &>/dev/null; then
    echo "ImageStream doesn't exist, creating"
    generate_payload | oc apply -f -
  fi
}

function write_imagestream_value() {
  oc label imagestream "${IMAGESTREAM_NAME}" opendatahub.io/notebook-image=${1} --overwrite
}

function verify_configmap_exists() {
  if ! oc get configmap "${CONFIGMAP_NAME}" &>/dev/null; then
    echo "Result ConfigMap doesn't exist, creating"
    oc create configmap "${CONFIGMAP_NAME}" --from-literal validation_result="false"
  fi
}

function write_configmap_value() {
  oc patch configmap "${CONFIGMAP_NAME}" -p '"data": { "validation_result": "'${1}'" }'
}

function write_last_valid_time() {
  oc patch configmap "${CONFIGMAP_NAME}" -p '"data": { "last_valid_time": "'$(date -Is)'" }'
}

function success() {
  echo "Validation succeeded, enabling image"
  verify_image_exists
  write_imagestream_value true
  verify_configmap_exists
  write_configmap_value true
  write_last_valid_time
}

function failure() {
  echo "Validation failed, disabling image"
  write_imagestream_value false
  verify_configmap_exists
  write_configmap_value false
}

CURL_RESULT=$(curl -w 'RESP_CODE:%{response_code}' -IHEAD "https://repo.anaconda.cloud/repo/t/$(get_variable Anaconda_ce_key)/main/noarch/repodata.json" 2>/dev/null)
CURL_CODE=$(echo "${CURL_RESULT}" | grep -o 'RESP_CODE:[1-5][0-9][0-9]'| cut -d':' -f2)

echo "Validation result: ${CURL_CODE}"

if [ "${CURL_CODE}" == 200 ]; then
  success
elif [ "${CURL_CODE}" == 403 ]; then
  failure
else
  echo "Return code ${CURL_CODE} from validation check, possibly upstream error. Exiting."
  echo "Result from curl:"
  echo "${CURL_RESULT}"
fi

exit 0
