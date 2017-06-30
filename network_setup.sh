#!/bin/bash

function usage () {
	echo
	echo "======================================================================================================"
	echo "Usage: "
	echo "      network_setup.sh -n [channel-name] -s -c -t [cli timer] -f [compose yaml] <up|down|retstart>"
	echo
	echo "      ./network_setup.sh -n "mychannel" -c -s -t 10  restart"
	echo
	echo "		-i       Image tag"
	echo "		-n       channel name"
	echo "		-c       enable couchdb"
	echo "		-f       Docker compose file for the network"
	echo "		-s       Enable TLS"
	echo "		-t       CLI container timeout"
	echo "		up       Launch the network and start the test"
	echo "		down     teardown the network and the test"
	echo "		restart  Restart the network and start the test"
	echo "======================================================================================================"
	echo
}

COMPOSE_FILE_COUCH=docker-compose-couch.yaml

while getopts "scn:f:t:i:h" opt; do
  case "${opt}" in
    i)
      FABRIC_IMAGE_TAG="$OPTARG"
      ;;
    n)
      CHANNEL_NAME="$OPTARG"
      ;;
    c)
      COUCHDB="y" ## enable couchdb
      ;;
    t)
      CLI_TIMEOUT=$OPTARG ## CLI container timeout
      ;;
    s)
      SECURITY="y" #Enable TLS
      ;;
    h)
      usage
      exit 1
      ;;
    f)
      COMPOSE_FILE="$OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      usage
      exit 1
      ;;
  esac
done

## this is to read the argument up/down/restart
shift $((OPTIND-1))
UP_DOWN="$@"

##Set Defaults
: ${FABRIC_IMAGE_TAG:="latest"}
: ${CHANNEL_NAME:="mychannel"}
: ${SECURITY:="n"}
: ${COMPOSE_FILE:="docker-compose.yaml"}
: ${UP_DOWN:="restart"}
: ${CLI_TIMEOUT:="2"} ## Increase timeout for debugging purposes
: ${COUCHDB:="n"}
export FABRIC_IMAGE_TAG
export CHANNEL_NAME
export CLI_TIMEOUT

function clearContainers () {
        CONTAINERS=$(docker ps -a|wc -l)
        if [ "$CONTAINERS" -gt "1" ]; then
                docker rm -f $(docker ps -aq)
        else
                printf "\n========== No containers available for deletion ==========\n"
        fi
}

function removeUnwantedImages() {
        DOCKER_IMAGE_IDS=$(docker images | grep "dev\|none\|test-vp\|peer[0-9]-" | awk '{print $3}')
        if [ -z "$DOCKER_IMAGE_IDS" -o "$DOCKER_IMAGE_IDS" = " " ]; then
                printf "\n========== No images available for deletion ==========\n"
        else
                docker rmi -f $DOCKER_IMAGE_IDS
        fi
}

function networkUp () {
    #Generate all the artifacts that includes org certs, orderer genesis block,
    # channel configuration transaction
    source generateArtifacts.sh $CHANNEL_NAME

    if [ "$SECURITY" == "y" -o "$SECURITY" == "Y" ]; then
        export ENABLE_TLS=true
    else
        export ENABLE_TLS=false
    fi
    if [ "$COUCHDB" == "y" -o "$COUCHDB" == "Y" ]; then
       docker-compose -f $COMPOSE_FILE -f $COMPOSE_FILE_COUCH up -d 2>&1
    else
       docker-compose -f $COMPOSE_FILE up -d 2>&1
    fi

    if [ $? -ne 0 ]; then
	echo "ERROR !!!! Unable to pull the images "
	exit 1
    fi
    docker logs -f cli
}

function networkDown () {
    docker-compose -f $COMPOSE_FILE -f $COMPOSE_FILE_COUCH down

    #Cleanup the chaincode containers
    clearContainers

    #Cleanup images
    removeUnwantedImages

    # remove orderer block and other channel configuration transactions and certs
    rm -rf channel-artifacts/*.block channel-artifacts/*.tx crypto-config
}

#Create the network using docker compose
if [ "${UP_DOWN}" == "up" ]; then
	networkUp
elif [ "${UP_DOWN}" == "down" ]; then ## Clear the network
	networkDown
elif [ "${UP_DOWN}" == "restart" ]; then ## Restart the network
	networkDown
	networkUp
else
	usage
	exit 1
fi
