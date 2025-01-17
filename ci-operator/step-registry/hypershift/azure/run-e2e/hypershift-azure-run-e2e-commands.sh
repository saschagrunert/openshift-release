#!/bin/bash

set +x

AZURE_AUTH_LOCATION="${CLUSTER_PROFILE_DIR}/osServicePrincipal.json"
if [[ "${USE_HYPERSHIFT_AZURE_CREDS}" == "true" ]]; then
    AZURE_AUTH_LOCATION="/etc/hypershift-ci-jobs-azurecreds/credentials.json"
fi
AZURE_AUTH_CLIENT_ID="$(<"${AZURE_AUTH_LOCATION}" jq -r .clientId)"
AZURE_AUTH_CLIENT_SECRET="$(<"${AZURE_AUTH_LOCATION}" jq -r .clientSecret)"
AZURE_AUTH_TENANT_ID="$(<"${AZURE_AUTH_LOCATION}" jq -r .tenantId)"

az --version
az login --service-principal -u "${AZURE_AUTH_CLIENT_ID}" -p "${AZURE_AUTH_CLIENT_SECRET}" --tenant "${AZURE_AUTH_TENANT_ID}" --output none

set -x

set -o nounset
set -o errexit
set -o pipefail
set -o xtrace

function cleanup() {
  for child in $( jobs -p ); do
    kill "${child}"
  done
  wait
}
trap cleanup EXIT

export EVENTUALLY_VERBOSE="false"

EXTERNAL_DNS_ARGS=""
if [[ "${HYPERSHIFT_EXTERNAL_DNS_DOMAIN:-}" != "" ]]; then
  EXTERNAL_DNS_ARGS="--e2e.external-dns-domain=${HYPERSHIFT_EXTERNAL_DNS_DOMAIN}"
fi

if [[ "${AKS}" == "true" ]]; then
  AKS_ANNOTATIONS=""
  HC_ANNOTATIONS_FILE="${SHARED_DIR}/hypershift_hc_annotations"

  if [[ -f "$HC_ANNOTATIONS_FILE" ]]; then
    while IFS= read -r line; do
      if [[ -n "$line" ]]; then
        AKS_ANNOTATIONS+=" --e2e.annotations=${line}"
      fi
    done < "$HC_ANNOTATIONS_FILE"
  fi
fi

if [[ -n "$HYPERSHIFT_MANAGED_SERVICE" ]]; then
    export MANAGED_SERVICE="$HYPERSHIFT_MANAGED_SERVICE"
fi

N1_NP_VERSION_TEST_ARGS=""
if [[ ${OCP_IMAGE_N1} != "${OCP_IMAGE_LATEST}" ]]; then
  N1_NP_VERSION_TEST_ARGS="--e2e.n1-minor-release-image=${OCP_IMAGE_N1}"
fi

N2_NP_VERSION_TEST_ARGS=""
if [[ ${OCP_IMAGE_N2} != "${OCP_IMAGE_LATEST}" ]]; then
  N2_NP_VERSION_TEST_ARGS="--e2e.n2-minor-release-image=${OCP_IMAGE_N2}"
fi

KEYVAULT_ARGS=""
if [[ "${AUTH_THROUGH_CERTS}" == "true" && "${TECH_PREVIEW_NO_UPGRADE}" == "true" ]]; then
  KEYVAULT_NAME="$(<"${SHARED_DIR}/azure_keyvault_name")"
  KEYVAULT_TENANT_ID="$(<"${SHARED_DIR}/azure_keyvault_tenant_id")"
  KEYVAULT_ARGS="--e2e.management-key-vault-name ${KEYVAULT_NAME} --e2e.management-key-vault-tenant-id ${KEYVAULT_TENANT_ID}"
fi

hack/ci-test-e2e.sh -test.v \
  -test.run='^TestCreateCluster.*|^TestNodePool$' \
  -test.parallel=20 \
  --e2e.platform=Azure \
  --e2e.azure-credentials-file=/etc/hypershift-ci-jobs-azurecreds/credentials.json \
  --e2e.pull-secret-file=/etc/ci-pull-credentials/.dockerconfigjson \
  --e2e.base-domain=hypershift.azure.devcluster.openshift.com \
  --e2e.azure-location=${HYPERSHIFT_AZURE_LOCATION} \
    ${EXTERNAL_DNS_ARGS:-} \
    ${AKS_ANNOTATIONS:-} \
    ${N1_NP_VERSION_TEST_ARGS:-} \
    ${N2_NP_VERSION_TEST_ARGS:-} \
    ${KEYVAULT_ARGS:-} \
  --e2e.latest-release-image="${OCP_IMAGE_LATEST}" \
  --e2e.previous-release-image="${OCP_IMAGE_PREVIOUS}" &
wait $!