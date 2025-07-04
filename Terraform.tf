---
format_version: '11'
default_step_lib_source: https://github.com/bitrise-io/bitrise-steplib.git

app:
  envs:
  - NODE_ENV: production
  - PIXELDRAIN_API_KEY: $PIXELDRAIN_API_KEY  # Set in Bitrise Secrets

workflows:
  setup_and_build:
    description: Setup environment, build Node.js app, and upload files recursively to Pixeldrain
    steps:
    - git-clone@12:
        inputs:
        - clone_depth: "1"

    - cache-pull@3:
        inputs:
        - cache_paths: |-
            ~/.npm
            node_modules

    - script@1:
        title: Install Node.js 18 and webtorrent-cli
        inputs:
        - content: |-
            #!/bin/bash
            set -e
            export NVM_DIR="$HOME/.nvm"
            if [ ! -d "$NVM_DIR" ]; then
              git clone https://github.com/nvm-sh/nvm.git "$NVM_DIR"
              cd "$NVM_DIR"
              git checkout `git describe --abbrev=0 --tags`
            fi
            . "$NVM_DIR/nvm.sh"
            nvm install 18
            nvm use 18

            echo "Installing webtorrent-cli globally"
            npm install -g webtorrent-cli

            node -v
            npm -v
            webtorrent --version || echo "webtorrent-cli installed"

    - npm@1:
        title: Install dependencies
        inputs:
        - command: ci

    - npm@1:
        title: Run tests
        inputs:
        - command: test

    - npm@1:
        title: Build application
        inputs:
        - command: run
        - args: build

    - cache-push@3:
        inputs:
        - cache_paths: |-
            ~/.npm
            node_modules

    - script@1:
        title: Recursively upload all files in build folders to Pixeldrain
        inputs:
        - content: |-
            #!/bin/bash
            set -e

            sudo apt-get update && sudo apt-get install -y curl || true

            UPLOAD_DIRS=("dist" "build")
            UPLOADED_LINKS=()

            for dir in "${UPLOAD_DIRS[@]}"; do
              if [ -d "$dir" ]; then
                echo "Uploading files from $dir recursively..."

                while IFS= read -r -d '' file; do
                  echo "Uploading $file ..."
                  RESPONSE=$(curl -s -F "file=@${file}" https://pixeldrain.com/api/file)
                  FILE_CODE=$(echo "$RESPONSE" | grep -oP '(?<="shortcode":")[^"]+')
                  if [ -z "$FILE_CODE" ]; then
                    echo "Failed to upload ${file}: $RESPONSE"
                    exit 1
                  fi
                  LINK="https://pixeldrain.com/u/$FILE_CODE"
                  echo "Uploaded $file: $LINK"
                  UPLOADED_LINKS+=("$file -> $LINK")
                done < <(find "$dir" -type f -print0)

              else
                echo "Directory $dir does not exist; skipping upload."
              fi
            done

            echo "UPLOADED_PIXELDRAIN_LINKS<<EOF" >> $BITRISE_ENV
            for link in "${UPLOADED_LINKS[@]}"; do
              echo "$link"
            done
            echo "EOF" >> $BITRISE_ENV

            echo "All files uploaded to Pixeldrain successfully."

  notify_failure:
    description: Send Slack notification on failure
    steps:
    - slack@3:
        inputs:
        - webhook_url: $SLACK_WEBHOOK_URL
        - message: ":warning: Build failed on Bitrise build $BITRISE_BUILD_NUMBER. Please investigate."

triggers:
  - push_branch:
      - main
      - release/*
    workflow: setup_and_build

  - workflow: notify_failure
    conditions:
      - '{{getenv "BITRISE_BUILD_STATUS"}} == "failed"'
