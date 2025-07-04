terraform {
  required_version = ">= 1.0"

  # Terraform Cloud backend configuration - replace with your details
  backend "remote" {
    organization = "AcmeKen"

    workspaces {
      name = "ideal-bassoon"
    }
  }

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.1"
    }
  }
}

provider "null" {}

variable "terraform_torrent_uri" {
  description = "Magnet or torrent link URI for downloading Terraform binary using webtorrent-cli"
  type        = string
  sensitive   = false
}

variable "pixeldrain_api_key" {
  description = "Pixeldrain API key if required (optional, not used for anonymous uploads)"
  type        = string
  sensitive   = true
  default     = ""
}

resource "null_resource" "webtorrent_pixeldrain_upload" {
  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -euo pipefail

# Variables (interpolated by Terraform)
TERRAFORM_TORRENT_URI="${var.terraform_torrent_uri}"
PIXELDRAIN_API_KEY="${var.pixeldrain_api_key}"
DOWNLOAD_DIR="${path.module}/terraform_bin"

# Install webtorrent-cli if missing
if ! command -v webtorrent > /dev/null 2>&1; then
  echo "Installing webtorrent-cli..."
  npm install -g webtorrent-cli
fi

# Install jq for JSON parsing (if missing)
if ! command -v jq > /dev/null 2>&1; then
  echo "jq not found, installing jq..."
  sudo apt-get update -y && sudo apt-get install -y jq
fi

mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR"

echo "Downloading Terraform via webtorrent-cli from $TERRAFORM_TORRENT_URI"
webtorrent download "$TERRAFORM_TORRENT_URI" --quiet --out .

TF_ZIP=$(ls *.zip | head -n 1)
if [ -z "$TF_ZIP" ]; then
  echo "Terraform zip file not found!"
  exit 1
fi

echo "Extracting $TF_ZIP"
unzip -o "$TF_ZIP" -d .

echo "Terraform binary contents:"
ls -l terraform

cd "${path.module}"

# Upload all files recursively from these directories to Pixeldrain
for dir in dist build; do
  if [ -d "$dir" ]; then
    echo "Uploading files from $dir recursively to Pixeldrain..."
    find "$dir" -type f | while read -r file; do
      echo "Uploading $file ..."
      response=$(curl -s -F "file=@${file}" https://pixeldrain.com/api/file)
      shortcode=$(echo "$response" | jq -r '.shortcode')
      if [[ -z "$shortcode" || "$shortcode" == "null" ]]; then
        echo "Upload failed for $file: $response"
        exit 1
      fi
      echo "Uploaded $file: https://pixeldrain.com/u/$shortcode"
    done
  else
    echo "Directory $dir does not exist, skipping."
  fi
done

echo "All files uploaded successfully."
EOT
    interpreter = ["/bin/bash", "-c"]
  }
}
