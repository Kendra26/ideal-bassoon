terraform {
  cloud {
    organization = "your-org"

    workspaces {
      name = "torrent-workspace"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_instance" "torrent_vm" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = "t3.micro"

  user_data = <<-EOF
    #!/bin/bash
    # Install dependencies
    sudo yum update -y
    sudo yum install -y wget curl nodejs npm

    # Install webtorrent-cli
    npm install -g webtorrent-cli

    # Download torrent file
    wget -O /home/ec2-user/file.torrent ${var.torrent_url}

    # Download torrent content
    webtorrent download /home/ec2-user/file.torrent --out /home/ec2-user/downloads --quiet

    # Upload dummy file with brackets
    FILE="/home/ec2-user/dummy_files/My Love [EZTVx.to].mkv"
    mkdir -p /home/ec2-user/dummy_files
    echo "This is a dummy file" > "$FILE"
    curl -T "$FILE" -u :${var.pixeldrain_api_key} https://pixeldrain.com/api/file/

    # Upload all downloaded files
    find /home/ec2-user/downloads -type f | while read -r file; do
      curl -T "$file" -u :${var.pixeldrain_api_key} https://pixeldrain.com/api/file/
    done
  EOF

  tags = {
    Name = "torrent-cloud-instance"
  }
}

variable "torrent_url" {
  default = "https://itorrents.org/torrent/27F160798A82E23608607455EB4064309C99DD63.torrent"
}

variable "pixeldrain_api_key" {
  description = "Pixeldrain API key"
  type        = string
  sensitive   = true
}
