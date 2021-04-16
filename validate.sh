#!/bin/sh

IMAGESTREAM_NAME='s2i-minimal-notebook-anaconda'
CONFIGMAP_NAME='anaconda-ce-validation-result'

function get_variable() {
  cat "/etc/secret-volume/${1}"
}

function verify_image_exists() {
  if ! oc get imagestream "${IMAGESTREAM_NAME}" &>/dev/null; then
    echo "ImageStream doesn't exist, creating"
    oc apply -f imagestream.yaml
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

function success() {
  echo "Validation succeeded, enabling image"
  verify_image_exists
  write_imagestream_value true
  verify_configmap_exists
  write_configmap_value true
}

function failure() {
  echo "Validation failed, disabling image"
  verify_image_exists
  write_imagestream_value false
  verify_configmap_exists
  write_configmap_value false
}

CURL_RESULT=$(curl -w 'RESP_CODE:%{response_code}' -IHEAD "https://repo.anaconda.cloud/repo/t/$(get_variable Anaconda_ce_key)/main/noarch/repodata.json" 2>/dev/null)
CURL_CODE=$(echo "${CURL_RESULT}" | grep -o 'RESP_CODE:[1-5][0-9][0-9]'| cut -d':' -f2)

echo "Validation result: ${CURL_CODE}"

if [ "${CURL_CODE}" == 200 ]; then
  success
  exit 0
elif [ "${CURL_CODE}" == 403 ]; then
  failure
  exit 1
else
  echo "Return code ${CURL_CODE} from validation check, possibly upstream error. Exiting."
  echo "Result from curl:"
  echo "${CURL_RESULT}"
  exit 2
fi
