#!/bin/bash

# Requires xmllint for XML parsing (install: sudo apt-get install libxml2-utils)
MANIFEST=".repo/manifests/default.xml"

# Extract the default revision from the manifest
DEFAULT_REVISION=$(xmllint --xpath 'string(//default/@revision)' "$MANIFEST")

function logerr() { echo -e "\033[1;31m$*\033[0m"; }
function logmsg() { echo -e "\033[0;33m$*\033[0m"; }
function logext() {
	echo -e "\033[1;31m$*\033[0m"
	exit 1
}

# Extract all projects' name, path, and revision attributes
xmllint --xpath '//project' "$MANIFEST" | \
  grep -oP 'name="\K[^"]+' | \
  while read -r PROJECT_NAME; do
    # Extract project path (if not set, use name as path)
    PROJECT_PATH=$(xmllint --xpath "string(//project[@name='$PROJECT_NAME']/@path)" "$MANIFEST")
    [ -z "$PROJECT_PATH" ] && PROJECT_PATH="$PROJECT_NAME"

    # Extract project revision (if not set, use default revision)
    PROJECT_REVISION=$(xmllint --xpath "string(//project[@name='$PROJECT_NAME']/@revision)" "$MANIFEST")
    [ -z "$PROJECT_REVISION" ] && PROJECT_REVISION="$DEFAULT_REVISION"

    # Check if the project directory exists
    if [ -d "$PROJECT_PATH" ]; then
		logmsg "[$PROJECT_PATH] -> checkout $PROJECT_REVISION"
		(
			cd "$PROJECT_PATH"
			# Check if the branch already exists locally
			if git show-ref --verify --quiet "refs/heads/$PROJECT_REVISION"; then
				logmsg "  > Branch   '$PROJECT_REVISION' already exists. Skipping checkout."
			else
				logmsg "  > Checkout '$PROJECT_REVISION'"
				git fetch origin "$PROJECT_REVISION"
				git checkout "$PROJECT_REVISION" || echo "  >> Branch does not exist: $PROJECT_REVISION"
			fi
		)
    else
		logmsg "[$PROJECT_PATH] directory does not exist, skipping"
	fi
done
