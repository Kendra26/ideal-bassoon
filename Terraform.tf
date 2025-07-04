terraform {
  required_version = ">= 1.0"

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

resource "null_resource" "webtorrent_pixeldrain_upload" {
  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -euo pipefail

# Ensure necessary dependencies are installed
if ! command -v webtorrent > /dev/null 2>&1; then
  echo "Installing webtorrent-cli..."
  npm install -g webtorrent-cli
fi

if ! command -v jq > /dev/null 2>&1; then
  echo "jq not found, installing jq..."
  sudo apt-get update -y && sudo apt-get install -y jq
fi

mkdir -p download

echo "Downloading Terraform via webtorrent-cli from magnet link"
webtorrent download "magnet:?xt=urn:btih:9187d47205935b83f5ed046ff03a19870658d187&dn=The.Land.Before.Time.VI.The.Secret.Of.Saurus.Rock.1998.720p.WEBRip.x264-%5BYTS.AM%5D.mp4&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce&tr=udp%3A%2F%2Fopen.demonii.com%3A1337%2Fannounce&tr=udp%3A%2F%2Ftracker.torrent.eu.org%3A451%2Fannounce" --out download

cd download

TF_ZIP=$(ls *.zip 2>/dev/null | head -n 1)

if [ -z "$TF_ZIP" ]; then
  echo "Terraform zip file not found!"
  exit 1
fi

echo "Extracting $TF_ZIP"
unzip -o "$TF_ZIP" -d .

echo "Terraform binary contents:"
ls -l terraform

cd "${path.module}"
EOT
    interpreter = ["/bin/bash", "-c"]
  }
}
