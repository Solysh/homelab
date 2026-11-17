#!/bin/bash
# Delete dangling (untagged) Docker images left behind by container updates,
# so they don't fill docker.img. Schedule: weekly in User Scripts.

mapfile -t IMAGES < <(docker images --quiet --filter "dangling=true")

if [ "${#IMAGES[@]}" -eq 0 ]; then
  echo "No dangling images."
  exit 0
fi

docker rmi "${IMAGES[@]}"
echo "Removed ${#IMAGES[@]} dangling image(s)."
