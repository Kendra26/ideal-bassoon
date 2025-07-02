format_version: '11'
default_step_lib_source: https://github.com/bitrise-io/bitrise-steplib.git
project_type: bash

workflows:
  torrent-download-upload:
    steps:
      - script@1:
          name: Checkout code
          run_if: |  
            true
      - script@1:
          name: Install dependencies
          run: |
            # Install webtorrent-cli
            npm install -g webtorrent-cli
      - script@1:
          name: Create dummy file with brackets in name
          run: |
            mkdir -p ./dummy_files
            echo "This is a dummy file" > "./dummy_files/My Love [EZTVx.to].mkv"
      - script@1:
          name: Download torrent content with webtorrent-cli
          run: |
            webtorrent download "magnet:?xt=urn:btih:FAF584A93A877E45EB83D98DDFEAF5AF3A010EC1&dn=Wang%20L.%20Control%20of%20Heavy%20Metals%20in%20the%20Environment%20Vol%202.%20Advanced%20Methods..2025&tr=udp://tracker.bittor.pw:1337/announce&tr=udp://tracker.opentrackr.org:1337/announce&tr=udp://tracker.dler.org:6969/announce&tr=udp://open.stealth.si:80/announce&tr=udp://tracker.torrent.eu.org:451/announce&tr=udp://exodus.desync.com:6969/announce&tr=udp://open.demonii.com:1337/announce" --out ./downloaded_files
      - script@1:
          name: Upload dummy file with brackets
          run: |
            file="./dummy_files/My Love [EZTVx.to].mkv"
            filename=$(basename "$file")
            echo "Uploading $filename..."
            curl -T "$file" -u :2828287337 "https://pixeldrain.com/api/file/"
      - script@1:
          name: Upload all downloaded files (escape brackets during upload)
          run: |
            find ./downloaded_files -type f | while read -r file; do
              filename=$(basename "$file")
              escaped_filename="$filename"
              if [[ "$filename" == *"["* || "$filename" == *"]"* ]]; then
                escaped_filename="${filename//\[/\\[}"
                escaped_filename="${escaped_filename//\]/\\]}"
              fi
              echo "Uploading $filename..."
              curl -T "$file" -u :2929288374 "https://pixeldrain.com/api/file/"
            done
