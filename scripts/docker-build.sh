#!/bin/bash
#
# (c) michael.wellner@de.ibm.com 2015.
#
# This script builds the docker image for the Dockerfile within the given directory, may modify proxy settings for Dockerfile if HTTP_PROXY is set within environment.
#
# Usage:
# docker-build.sh [ -h | --help | OPTIONS ]
#
# Options:
#   -p|--project
#     The project to be build (directory names in dockerfiles/, e.g. base-dev, ibm-iib, ...).
#   -d|--download-host
#     Optional.
#     The host to download the installation files.
#   -p|--download-port
#     Optional. Default: 8080.
#     The of the download-host to download the installation files.
#   --no-download
#     Optional.
#     Set this argument to true if no download-host should be set.
#   -t|--tagname
#     Optional. Default: ${PROJECT}.
#     The tagname of the docker image - Will be prefixed with 'ibm/...'.
#   --http-proxy
#     Optional. Default: ${http_proxy}.
#     The http proxy.
#   --https-proxy
#     Optional. Default: ${https_proxy}.
#     The https proxy.
#   --no-proxy
#     Optional. Default: ${no_proxy}.
#     Ignore proxy domains.
#

# Fail if one of the commands fails
set -e

CURRENTDIR=`pwd`
BASEDIR=$(dirname $0)
PROJECT=
DOWNLOAD_HOST=
DOWNLOAD_PORT=
NO_DOWNLOAD=
TAGNAME=
HTTP_PROXY=
HTTPS_PROXY=
NO_PROXY=


main() {
  cd ${BASEDIR}
  read_variables "$@"
  check_required
  init_defaults

  HTTP_SERVER_RUNNING=$(./docker-exec.sh --args ps | grep "http-server" > /dev/null && echo 0 || echo 1)
  SKYDOCK_RUNNING=$(./docker-exec.sh --args ps | grep "skydock" > /dev/null && echo 0 || echo 1)

  echo "HTTP Server running: ${HTTP_SERVER_RUNNING}"
  echo "Skydock running: ${SKYDOCK_RUNNING}"

  NO_PROXY=${NO_PROXY}

  if [ -z ${DOWNLOAD_HOST} ] && [ ${SKYDOCK_RUNNING} -eq 0 ] && [ ${HTTP_SERVER_RUNNING} -eq 0 ]; then
  	ENV=$(./docker-exec.sh --args inspect skydock | grep -A 1 "environment" | tail -n 1 | awk -F\" '{print $2}')
  	DOMAIN=$(./docker-exec.sh --args inspect skydns | grep -A 1 "domain" | tail -n 1 | awk -F\" '{print $2}')

  	DOWNLOAD_HOST="http-server.${ENV}.${DOMAIN}"
  	NO_PROXY=".${ENV}.${DOMAIN},${NO_PROXY}"

  	echo "Determined ${DOWNLOAD_HOST} as download-host ..."
  elif [ -z ${DOWNLOAD_HOST} ] && [ ${HTTP_SERVER_RUNNING} -eq 0 ]; then
  	DOWNLOAD_HOST=`./docker-exec.sh --args inspect http-server | grep "\"IPA" | awk -F\" '{ print $4 }'`
  	NO_PROXY="${DOWNLOAD_HOST},${NO_PROXY}"

  	echo "Determined ${DOWNLOAD_HOST} as download-host ..."
  fi

  DOWNLOAD_BASE_URL="${DOWNLOAD_HOST}:${DOWNLOAD_PORT}"
  echo "Using ${DOWNLOAD_BASE_URL} for installation files ..."

  if [ ! -z ${HTTP_PROXY} ]; then
  	echo "Using proxy ${HTTP_PROXY} to build ${PROJECT}/Dockerfile ..."

  	NEED_HTTP=$(cat ../dockerfiles/${PROJECT}/Dockerfile | grep "FROM ubuntu" > /dev/null && echo 0 || echo 1)

  	HTTP_PROXY=`echo ${HTTP_PROXY} | sed "s#http://\([\.]*\)#\1#g"`
  	HTTPS_PROXY=`echo ${HTTPS_PROXY} | sed "s#http://\([\.]*\)#\1#g"`
  	NO_PROXY=`echo "${NO_PROXY}" | sed "s# ##g" | sed "s#[[:blank:]]##g" | sed "s#[[:space:]]##g"`

  	if [ ${NEED_HTTP} -eq 0 ]; then
  		echo "Using Proxy with http:// ..."
  		HTTP_PROXY="http://${HTTP_PROXY}"
  		HTTPS_PROXY="http://${HTTPS_PROXY}"
  	fi

  	cat ../dockerfiles/${PROJECT}/Dockerfile | sed "s#http_proxy_disabled#http_proxy=${HTTP_PROXY}#g" > ../dockerfiles/${PROJECT}/Dockerfile.proxy
  	./sed.sh --args "s#https_proxy_disabled#https_proxy=${HTTPS_PROXY}#g" ../dockerfiles/${PROJECT}/Dockerfile.proxy
  	./sed.sh --args "s#no_proxy_disabled#no_proxy=\"${NO_PROXY}\"#g" ../dockerfiles/${PROJECT}/Dockerfile.proxy

  	if [ ! "${DOWNLOAD_HOST}" = "" ]; then
  		./sed.sh --args "s#DOWNLOAD_BASE_URL=\"\([^\"]*\)\"#DOWNLOAD_BASE_URL=\"${DOWNLOAD_BASE_URL}\"#g" ../dockerfiles/${PROJECT}/Dockerfile.proxy
  	fi

  	echo "Transformed Dockerfile:"
  	echo "######################################################################"
  	cat ../dockerfiles/${PROJECT}/Dockerfile.proxy
  	echo "######################################################################"

  	./docker-exec.sh --args build -t ibm/${TAGNAME} -f ../dockerfiles/${PROJECT}/Dockerfile.proxy ../dockerfiles/${PROJECT}/
  	rm ../dockerfiles/${PROJECT}/Dockerfile.proxy
  else
  	if [ "${DOWNLOAD_HOST}" = "" ]; then
  		cat ../dockerfiles/${PROJECT}/Dockerfile > ../dockerfiles/${PROJECT}/Dockerfile.tmp
  	else
  		cat ../dockerfiles/${PROJECT}/Dockerfile | sed "s#DOWNLOAD_BASE_URL=\"\([^\"]*\)\"#DOWNLOAD_BASE_URL=\"${DOWNLOAD_BASE_URL}\"#g" > ../dockerfiles/${PROJECT}/Dockerfile.tmp
  	fi

  	echo "Transformed Dockerfile:"
  	echo "######################################################################"
  	cat ../dockerfiles/${PROJECT}/Dockerfile.tmp
  	echo "######################################################################"

  	./docker-exec.sh --args build -t ibm/${TAGNAME} -f ../dockerfiles/${PROJECT}/Dockerfile.tmp ../dockerfiles/${PROJECT}/
  	rm ../dockerfiles/${PROJECT}/Dockerfile.tmp
  fi
  cd ${CURRENTDIR}
}

check_required() {
  if [ -z "${PROJECT}" ]; then
    >&2 echo "Missing required parameter: -p|--project."
    show_help_and_exit 1
  fi;
}

init_defaults() {
	if [ -z "${DOWNLOAD_PORT}" ]; then
	  DOWNLOAD_PORT="8080"
	fi;
	if [ -z "${TAGNAME}" ]; then
	  TAGNAME="${PROJECT}"
	fi;
	if [ -z "${HTTP_PROXY}" ]; then
	  HTTP_PROXY="${http_proxy}"
	fi;
	if [ -z "${HTTPS_PROXY}" ]; then
	  HTTPS_PROXY="${https_proxy}"
	fi;
	if [ -z "${NO_PROXY}" ]; then
	  NO_PROXY="${no_proxy}"
	fi;
}

read_variables() {
  while [[ $# -gt 0 ]]
  do
    key="$1"
    case $key in
      -p|--project)
        PROJECT="$2";;
      -d|--download-host)
        DOWNLOAD_HOST="$2";;
      -p|--download-port)
        DOWNLOAD_PORT="$2";;
      --no-download)
        NO_DOWNLOAD="$2";;
      -t|--tagname)
        TAGNAME="$2";;
      --http-proxy)
        HTTP_PROXY="$2";;
      --https-proxy)
        HTTPS_PROXY="$2";;
      --no-proxy)
        NO_PROXY="$2";;
      -h|--help)
        show_help_and_exit 0;;
      *)
        >&2 echo "Unkown option $1 with value $2."
        echo
        show_help_and_exit 2
        ;;
    esac
    shift # past argument
    shift # past argument
  done
}

show_help_and_exit() {
  echo "This script builds the docker image for the Dockerfile within the given directory, may modify proxy settings for Dockerfile if HTTP_PROXY is set within environment."
  echo ""
  echo "Usage:"
  echo "docker-build.sh [ -h | --help | OPTIONS ]"
  echo ""
  echo "Options:"
  echo "  -p|--project"
  echo "    The project to be build (directory names in dockerfiles/, e.g. base-dev, ibm-iib, ...)."
  echo "  -d|--download-host"
  echo "    Optional."
  echo "    The host to download the installation files."
  echo "  -p|--download-port"
  echo "    Optional. Default: 8080."
  echo "    The of the download-host to download the installation files."
  echo "  --no-download"
  echo "    Optional."
  echo "    Set this argument to true if no download-host should be set."
  echo "  -t|--tagname"
  echo "    Optional. Default: \${PROJECT}."
  echo "    The tagname of the docker image - Will be prefixed with 'ibm/...'."
  echo "  --http-proxy"
  echo "    Optional. Default: \${http_proxy}."
  echo "    The http proxy."
  echo "  --https-proxy"
  echo "    Optional. Default: \${https_proxy}."
  echo "    The https proxy."
  echo "  --no-proxy"
  echo "    Optional. Default: \${no_proxy}."
  echo "    Ignore proxy domains."
  echo
  sleep 3

  cd ${CURRENTDIR}
  exit $1
}


main "$@"
