terraform {
  required_version = ">= 1.0"

  # Using Terraform Cloud as the backend to store state remotely
  backend "remote" {
    organization = "AckmeKen"

    workspaces {
      name = "ideal-bassoon"
    }
  }

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "null" {}

# Local-exec provisioner to download files using webtorrent-cli and upload files recursively to Pixeldrain
resource "null_resource" "webtorrent_pixeldrain_upload" {
  provisioner "local-exec" {
    command = <<EOT
      set -e

      # Install webtorrent-cli if not installed
      if ! command -v webtorrent > /dev/null 2>&1; then
        echo "Installing webtorrent-cli..."
        npm install -g webtorrent-cli
      fi

      # Define variables
      TERRAFORM_TORRENT_URI="${var.terraform_torrent_uri}"
      DOWNLOAD_DIR="${path.module}/terraform_bin"
      UPLOAD_DIRS=("dist" "build")
      PIXELDRAIN_API_KEY="${var.pixeldrain_api_key}"

      mkdir -p "$DOWNLOAD_DIR"
      cd "$DOWNLOAD_DIR"

      # Download Terraform zip using webtorrent-cli (magnet or torrent file URI)
      echo "Downloading Terraform via webtorrent-cli from $TERRAFORM_TORRENT_URI"
      webtorrent download "$TERRAFORM_TORRENT_URI" --quiet --out .

      # Find the downloaded .zip file (assuming only one zip)
      TF_ZIP=$(ls *.zip | head -n 1)
      if [ -z "$TF_ZIP" ]; then
        echo "Terraform zip file not found!"
        exit 1
      fi

      echo "Extracting $TF_ZIP"
      unzip -o "$TF_ZIP" -d .

      echo "Downloading completed; Terraform binary should be here:"
      ls -l terraform

      # Go back to module path for uploading files
      cd "${path.module}"

      # Function to upload a file to Pixeldrain
      upload_file_to_pixeldrain() {
        local file="$1"
        echo "Uploading $file to Pixeldrain..."
        response=$(curl -s -F "file=@$file" https://pixeldrain.com/api/file)
        shortcode=$(echo "$response" | jq -r '.shortcode')
        if [ -z "$shortcode" ] || [ "$shortcode" = "null" ]; then
          echo "Upload failed for $file: $response"
          exit 1
        fi
        echo "File $file uploaded: https://pixeldrain.com/u/$shortcode"
      }

      # Check jq is installed
      if ! command -v jq > /dev/null 2>&1; then
        echo "jq is required for JSON parsing. Please install jq."
        exit 1
      fi

      # Upload files recursively from each directory
      for dir in "${UPLOAD_DIRS[@]}"; do
        if [ -d "$dir" ]; then
          echo "Uploading contents of $dir recursively..."
          find "$dir" -type f | while read -r file; do
            upload_file_to_pixeldrain "$file"
          done
        else
          echo "Directory $dir does not exist; skipping upload."
        fi
      done

      echo "All files uploaded successfully."
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

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
