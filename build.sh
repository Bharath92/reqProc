#!/bin/bash -e

export ARCHITECTURE="$1"
export OS="$2"
export HUB_ORG="$3"
export IMAGE_NAME="$4"
export TAG="master"
export HUB_IMAGE="$HUB_ORG/$IMAGE_NAME:$TAG"

check_input() {
  if [ -z "$ARCHITECTURE" ]; then
    echo "Missing input parameter ARCHITECTURE"
    exit 1
  fi

  if [ -z "$OS" ]; then
    echo "Missing input parameter OS"
    exit 1
  fi

  if [ -z "$HUB_ORG" ]; then
    echo "Missing input parameter HUB_ORG"
    exit 1
  fi

  if [ -z "$IMAGE_NAME" ]; then
    echo "Missing input parameter IMAGE_NAME"
    exit 1
  fi
}

set_build_context() {
  # sed -i syntax is different on macOS
  if [ "$OS" == "macOS_10.12" ]; then
    sed -i "" "s/{{%TAG%}}/$TAG/g" ./image/$ARCHITECTURE/$OS/Dockerfile
  else
    sed -i "s/{{%TAG%}}/$TAG/g" ./image/$ARCHITECTURE/$OS/Dockerfile
  fi
}

build_and_tag_image() {
  docker build -f ./image/$ARCHITECTURE/$OS/Dockerfile -t "$HUB_IMAGE" .
}

push_images() {
  docker push "$HUB_IMAGE"
}

main() {
  check_input
  set_build_context
  build_and_tag_image
  push_images
}

main
