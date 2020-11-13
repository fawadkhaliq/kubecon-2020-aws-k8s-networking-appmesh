#!/bin/bash

set -eo pipefail

AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d. -f1)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
PROJECT_NAME="appmesh-outlier-detection"
APP_NAMESPACE=${PROJECT_NAME}
MESH_NAME=${PROJECT_NAME}
CLOUDMAP_NAMESPACE="${PROJECT_NAME}.pvt.aws.local"

DH_BASE="fawadkhaliq"
FRONT_APP_IMAGE="${DH_BASE}/feapp"
COLOR_APP_IMAGE="${DH_BASE}/colorapp"
VEGETA_IMAGE="${DH_BASE}/vegeta-trafficgen"

MANIFEST_VERSION="${1:-v1beta2}"

error() {
    echo $1
    exit 1
}

check_virtualnode_v1beta2(){
    #check CRD
    crd=$(kubectl get crd virtualnodes.appmesh.k8s.aws -o json | jq -r '.. | .awsCloudMap?.properties.namespaceName? | select(. != null)')
    if [ -z "$crd" ]; then
        error "$PROJECT_NAME requires virtualnodes.appmesh.k8s.aws CRD to support Cloud Map service-discovery. See https://github.com/aws/aws-app-mesh-controller-for-k8s/blob/master/CHANGELOG.md"
    else
        echo "CRD check passed!"
    fi
}

check_appmesh_k8s() {
    #check aws-app-mesh-controller version
    if [ "$MANIFEST_VERSION" = "v1beta2" ]; then
        currentver=$(kubectl get deployment -n appmesh-system appmesh-controller -o json | jq -r ".spec.template.spec.containers[].image" | cut -f2 -d ':'|tail -n1)
        requiredver="v1.2.0"
        check_virtualnode_v1beta2
    else
        error "$PROJECT_NAME unexpected manifest version input: $MANIFEST_VERSION. Timeouts are only supported in v1beta2 and AppMesh controller version >= v1.2.0. See https://github.com/aws/aws-app-mesh-controller-for-k8s/blob/master/CHANGELOG.md"
    fi

    if [ "$(printf '%s\n' "$requiredver" "$currentver" | sort -V | head -n1)" = "$requiredver" ]; then
        echo "aws-app-mesh-controller check passed! $currentver >= $requiredver"
    else
        error "$PROJECT_NAME requires aws-app-mesh-controller version >=$requiredver but found $currentver. See https://github.com/aws/aws-app-mesh-controller-for-k8s/blob/master/CHANGELOG.md"
    fi
}

setup_cloudmap_ns() {
    nsId=($(aws servicediscovery list-namespaces |
        jq -r ".Namespaces[] | select(.Name | contains(\"${CLOUDMAP_NAMESPACE}\")) | .Id"))

    if [ -z "${nsId}" ]; then
        if [ -z "${VPC_ID}" ]; then
            echo "VPC_ID must be set. VPC_ID corresponds to vpc where applications are deployed."
	    echo "You can run 'aws eks describe-cluster --name $CLUSTER_NAME | jq .cluster.resourcesVpcConfig.vpcId' find to VPC ID"
            exit 1
        fi

        aws servicediscovery create-private-dns-namespace \
            --name "${CLOUDMAP_NAMESPACE}" \
            --vpc "${VPC_ID}"
        echo "Created private-dns-namespace ${CLOUDMAP_NAMESPACE}"
        sleep 5
    fi
}

deploy_app() {
    OUTPUT_DIR="${DIR}/_output/"
    mkdir -p ${OUTPUT_DIR}
    eval "cat <<EOF
$(<${DIR}/${MANIFEST_VERSION}/manifest.yaml.template)
EOF
" >${OUTPUT_DIR}/manifest.yaml

    kubectl apply -f ${OUTPUT_DIR}/manifest.yaml
}

main() {
    check_appmesh_k8s
    setup_cloudmap_ns
    deploy_app
}

main
