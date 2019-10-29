#!/bin/sh
set -e

# Jet Bridge
# https://github.com/jet-admin/jet-bridge
#
# This script is meant for quick & easy install via:
#
#   sh <(curl -s https://raw.githubusercontent.com/jet-admin/jet-bridge/dev/install_jet.sh)


PROJECT=$1
TOKEN=$2

if [ "$(uname)" == "Darwin" ]; then
    MAC=1
else
    MAC=0
fi

if [[ $(uname -s) == CYGWIN* ]];then
    WIN=1
else
    WIN=0
fi

if [ $WIN -eq 1 ] || [ $MAC -eq 1 ]; then
    NET="bridge"
else
    NET="host"
fi

check_arguments() {
    if [[ -z $PROJECT ]]; then
        echo
        echo "ERROR:"
        echo "    Pass project as an argument"
        echo
        exit 1
    fi
    if [[ -z $TOKEN ]]; then
        echo
        echo "ERROR:"
        echo "    Pass token as an argument"
        echo
        exit 1
    fi
}

remove_container() {
    docker rm --force ${CONTAINER_NAME} &> /dev/null || true
}

check_is_docker_installed() {
    # Check if docker is installed
    if ! [ -x "$(command -v docker)" ]; then
        echo
        echo "ERROR:"
        echo "    Docker is not found on your system"
        echo "    Install Docker by running the following command:"
        echo
        echo "        sh <(curl -s https://get.docker.com)"
        echo
        echo "    or follow official documentation"
        echo
        echo "        https://docs.docker.com/install/"
        echo
        exit 1
    fi
}

check_is_docker_running() {
    # Check if docker is running
    docker info &> /dev/null && { docker_state=1; } || { docker_state=0; }

    if [ $docker_state != 1 ]; then
        echo
        echo "ERROR:"
        echo "    Docker does not seem to be running, run it first and retry"
        echo
        exit 1
    fi
}

fetch_latest_jet_bridge() {
    echo
    echo "    Fetching latest Jet Bridge image..."
    echo

    docker pull jetadmin/jetbridge:dev
}

prepare_container() {
    echo
    echo "    Installing Jet Bridge as a Docker container..."
    echo

    read -p "Enter Docker container name or leave default [jet_bridge]: " CONTAINER_NAME
    CONTAINER_NAME=${CONTAINER_NAME:-jet_bridge}
}

create_config() {
    POSSIBLE_HOST=''

    if [ $WIN -eq 1 ] || [ $MAC -eq 1 ]; then
        remove_container
        POSSIBLE_HOST=$(docker run \
            --name=${CONTAINER_NAME} \
            -it \
            -v $(pwd):/jet \
            --entrypoint=/network-entrypoint.sh \
            --net=host \
            jetadmin/jetbridge:dev)
    fi

    POSSIBLE_HOST="${POSSIBLE_HOST:-localhost}"

    remove_container
    docker run \
        --name=${CONTAINER_NAME} \
        -it \
        -v $(pwd):/jet \
        -e PROJECT=${PROJECT} \
        -e TOKEN=${TOKEN} \
        -e DATABASE_HOST=${POSSIBLE_HOST} \
        -e POSSIBLE_HOST=${POSSIBLE_HOST} \
        -e ARGS=config \
        --net=${NET} \
        jetadmin/jetbridge:dev
}

run_instance() {
    PORT=$(awk -F "=" '/^PORT=/ {print $2}' jet.conf)
    CONFIG_FILE="${PWD}/jet.conf"
    RUN_TIMEOUT=$(awk -F "=" '/^RUN_TIMEOUT=/ {print $2}' jet.conf)
    RUN_TIMEOUT="${RUN_TIMEOUT:-10}"

    echo
    echo "    Starting Jet Bridge..."

    remove_container
    docker run \
        -p ${PORT}:${PORT} \
        --name=${CONTAINER_NAME} \
        -v $(pwd):/jet \
        --net=${NET} \
        --restart=always \
        -d \
        jetadmin/jetbridge:dev \
        1> /dev/null

    BASE_URL="http://localhost:${PORT}/api/"
    REGISTER_URL="${BASE_URL}register/"

    printf '    '

    i=0
    DELAY=1
    TIMEOUT=10
    i_last=$((TIMEOUT / DELAY))

    until $(curl --output /dev/null --silent --fail ${BASE_URL}); do
        printf '.'
        sleep $DELAY
        (( count++ ))

        if [[ count -ge $i_last ]]; then
            echo
            echo
            echo "ERROR:"
            echo "    Jet Bridge failed to start after timeout (${TIMEOUT}):"
            echo

            docker logs ${CONTAINER_NAME}

            exit 1
        fi
    done

    if command -v python &>/dev/null; then
        python -mwebbrowser ${REGISTER_URL}
    fi

    echo
    echo "    To stop:"
    echo "        docker stop ${CONTAINER_NAME}"
    echo
    echo "    To start:"
    echo "        docker start ${CONTAINER_NAME}"
    echo
    echo "    To view logs:"
    echo "        docker logs -f ${CONTAINER_NAME}"
    echo
    echo "    To view token:"
    echo "        docker exec -it ${CONTAINER_NAME} jet_bridge token"
    echo
    echo "    Success! Jet Bridge is now running and will start automatically on system reboot"
    echo
    echo "    Port: ${PORT}"
    echo "    Docker Container: ${CONTAINER_NAME}"
    echo "    Config File: ${CONFIG_FILE}"
    echo
    echo "    Open http://localhost:${PORT}/api/register/ to finish installation"
    echo
}

check_arguments
check_is_docker_installed
check_is_docker_running
fetch_latest_jet_bridge
prepare_container
create_config
run_instance
