terraform {
  cloud {
    organization = "AcmeKen"

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
    mkdir downloads 

    # Download torrent content
    webtorrent download "magnet:?xt=urn:btih:FAF584A93A877E45EB83D98DDFEAF5AF3A010EC1&dn=Wang%20L.%20Control%20of%20Heavy%20Metals%20in%20the%20Environment%20Vol%202.%20Advanced%20Methods..2025&tr=udp://tracker.bittor.pw:1337/announce&tr=udp://tracker.opentrackr.org:1337/announce&tr=udp://tracker.dler.org:6969/announce&tr=udp://open.stealth.si:80/announce&tr=udp://tracker.torrent.eu.org:451/announce&tr=udp://exodus.desync.com:6969/announce&tr=udp://open.demonii.com:1337/announce" --out downloads

    # Upload dummy file with brackets
    FILE="/home/ec2-user/dummy_files/My Love [EZTVx.to].mkv"
    mkdir -p /home/ec2-user/dummy_files
    echo "This is a dummy file" > "$FILE"
    curl -T "$FILE" -u :1627383993 https://pixeldrain.com/api/file/

    # Upload all downloaded files
    find /downloads -type f | while read -r file; do
      curl -T "$file" -u :26278288282828 https://pixeldrain.com/api/file/
    done
  EOF

  tags = {
    Name = "torrent-cloud-instance"
  }
}
