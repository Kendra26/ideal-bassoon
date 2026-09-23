terraform {
  required_version = ">= 1.0.0"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {}

resource "docker_image" "ubuntu" {
  name         = "ubuntu:22.04"
  keep_locally = false
}

resource "docker_container" "media_processor" {
  name  = "media-processor-runner"
  image = docker_image.ubuntu.image_id

  entrypoint = ["/bin/bash", "-c"]
  command = [
    <<-EOF
    set -e
    echo "📦 Installing system dependencies..."
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y p7zip-full python3-pip python3-libtorrent curl git

    python3 -m pip install --upgrade pip --break-system-packages || true
    python3 -m pip install --no-cache-dir magnet2torrent requests natsort libtorrent --break-system-packages || true

    mkdir -p /app/downloads /app/torrents
    cd /app

    echo "🧲 Step 1: Processing Links & Converting Magnets..."
    python3 - << 'PYEOF'
import asyncio
import os
import requests
from urllib.parse import urlparse
from magnet2torrent import Magnet2Torrent

link_url = "https://pink-script-snap.lovable.app/api/public/page/0e01cfaf-128c-477f-bff1-9dee23822d97.txt"

async def main():
    try:
        ks = requests.get(link_url, timeout=10).text
        if "STOP.ALL.TORRENTS" in ks:
            print("🛑 Global kill switch active.")
            return
            
        direct_links = []
        for i, link in enumerate(ks.splitlines()):
            link = link.strip()
            if link and not link.startswith('#') and not link.endswith(' NO'):
                if link.startswith('magnet:'):
                    print(f"📥 Converting magnet: {link[:60]}...", flush=True)
                    try:
                        m2t = Magnet2Torrent(link)
                        filename, torrent_data = await asyncio.wait_for(m2t.retrieve_torrent(), timeout=30)
                        torrent_path = os.path.join("torrents", f"{filename}.torrent")
                        with open(torrent_path, "wb") as f:
                            f.write(torrent_data)
                        print(f"✅ Saved torrent: {torrent_path}")
                    except Exception as e:
                        print(f"⚠️ Magnet conversion failed ({e}). Queuing for libtorrent fallback!", flush=True)
                        direct_links.append(link)
                elif link.startswith('http'):
                    if link.endswith('.torrent'):
                        try:
                            tor_data = requests.get(link, timeout=15).content
                            parsed = urlparse(link)
                            filename = os.path.basename(parsed.path) or f"download_{i}.torrent"
                            with open(os.path.join('torrents', filename), 'wb') as tf:
                                tf.write(tor_data)
                            print(f"✅ Downloaded .torrent: {filename}")
                        except Exception as e:
                            print(f"❌ Failed to download torrent file ({e}): {link}")
                    else:
                        direct_links.append(link)
                        print(f"🔗 Queued direct HTTP download: {link}")
                        
        if direct_links:
            with open('direct_links.txt', 'w') as f:
                f.write('\n'.join(direct_links))
                
    except Exception as e:
        print(f"Error processing links: {e}")

asyncio.run(main())
PYEOF

    echo "🚀 Step 2: Downloading Torrents & Direct Links..."
    python3 -u - << 'PYEOF'
import os
import glob
import asyncio
import time
import requests
import libtorrent as lt
from natsort import natsorted

def get_best_trackers():
    fallback_trackers = [
        "udp://tracker.openbittorrent.com:80/announce",
        "udp://tracker.opentrackr.org:1337/announce",
        "udp://tracker.torrent.eu.org:451/announce",
        "udp://exodus.desync.com:6969/announce",
        "udp://open.stealth.si:80/announce"
    ]
    try:
        url = "https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_best.txt"
        res = requests.get(url, timeout=5)
        if res.status_code == 200:
            fetched = [line.strip() for line in res.text.splitlines() if line.strip()]
            if fetched: return fetched
    except Exception:
        pass
    return fallback_trackers

LIVE_TRACKERS = get_best_trackers()
ses = lt.session({'listen_interfaces': '0.0.0.0:6881'})

def format_eta(seconds):
    if seconds <= 0: return "Unknown"
    m, s = divmod(int(seconds), 60)
    h, m = divmod(m, 60)
    return f"{h}h {m}m {s}s" if h > 0 else f"{m}m {s}s"

async def download_target(target, sem):
    async with sem:
        if target.startswith('http') and not target.endswith('.torrent'):
            print(f"📥 Direct HTTP download: {target[:80]}", flush=True)
            try:
                parsed = requests.utils.urlparse(target)
                fname = os.path.basename(parsed.path) or f"download_{time.time()}"
                dest = os.path.join("downloads", fname)
                with requests.get(target, stream=True, timeout=15) as r:
                    r.raise_for_status()
                    total_len = r.headers.get('content-length')
                    with open(dest, 'wb') as f:
                        if total_len is None:
                            for chunk in r.iter_content(chunk_size=8192):
                                if chunk: f.write(chunk)
                        else:
                            dl = 0
                            total_len = int(total_len)
                            start_time = time.time()
                            last_p_time = time.time()
                            for chunk in r.iter_content(chunk_size=8192):
                                if chunk:
                                    dl += len(chunk)
                                    f.write(chunk)
                                    cur_time = time.time()
                                    if cur_time - last_p_time >= 30:
                                        speed = dl / (cur_time - start_time)
                                        eta_str = format_eta((total_len - dl) / speed) if speed > 0 else "Unknown"
                                        pct = (dl / total_len) * 100
                                        print(f"📊 Progress [{fname[:25]}]: {pct:.2f}% | Speed: {speed/1024:.1f} KiB/s | ETA: {eta_str}", flush=True)
                                        last_p_time = cur_time
                print(f"✅ Finished: {target[:80]}", flush=True)
                return target
            except Exception as e:
                print(f"❌ Failed: {e}", flush=True)
                return None

        handle = None
        try:
            if target.startswith('magnet:'):
                params = lt.parse_magnet_uri(target)
                params.save_path = 'downloads'
                handle = ses.add_torrent(params)
            else:
                info = lt.torrent_info(target)
                params = {'save_path': 'downloads', 'ti': info}
                handle = ses.add_torrent(params)
                
            for tr in LIVE_TRACKERS:
                handle.add_tracker({'url': tr})
                
            last_print_time = time.time()
            while True:
                s = handle.status()
                if s.is_finished or s.progress >= 1.0 or getattr(s, 'is_seeding', False):
                    break
                    
                current_time = time.time()
                if current_time - last_print_time >= 30:
                    rate = s.download_payload_rate
                    eta_str = format_eta((s.total_wanted - s.total_wanted_done) / rate) if rate > 0 else "Unknown"
                    prog = s.progress * 100
                    name = s.name or "metadata_pending"
                    print(f"📊 Progress [{name[:25]}]: {prog:.2f}% | Speed: {rate/1024:.1f} KiB/s | ETA: {eta_str}", flush=True)
                    last_print_time = current_time
                    
                await asyncio.sleep(2)
                
            print(f"✅ Downloaded: {target[:80]}", flush=True)
            ses.remove_torrent(handle)
            return target
        except Exception as e:
            print(f"❌ Error: {e}", flush=True)
            if handle: ses.remove_torrent(handle)
            return None

async def main():
    targets = natsorted(glob.glob("torrents/*.torrent"))
    if os.path.exists("direct_links.txt"):
        with open("direct_links.txt", "r") as f:
            targets.extend(natsorted([line.strip() for line in f if line.strip()]))
            
    if targets:
        sem = asyncio.Semaphore(16)
        tasks = [download_target(t, sem) for t in targets]
        await asyncio.gather(*tasks)

asyncio.run(main())
PYEOF

    echo "📦 Step 3: Sanitizing Names & Zipping Packages..."
    python3 - << 'PYEOF'
import os, shutil, subprocess, re
from collections import defaultdict
from natsort import natsorted

folder = "downloads"
video_ext = ('.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.m4v')
media_ext = video_ext + ('.srt', '.ass', '.vtt', '.sub')
PART_SIZE_LIMIT = 5000 * 1024 * 1024

def sanitize_name(name):
    s = re.sub(r'[^\w\.\-]', '_', name)
    return re.sub(r'_+', '_', s).strip('_') or "archive"

def create_7z_group(group_name, file_paths, base_dir):
    clean_group_name = sanitize_name(group_name)
    all_items = []
    seen_paths = set()

    for p in file_paths:
        if not os.path.exists(p) or p in seen_paths: continue
        item_files = [p]
        seen_paths.add(p)

        base_stem = os.path.splitext(p)[0]
        for sub_ext in ('.srt', '.ass', '.vtt', '.sub'):
            sub_file = base_stem + sub_ext
            if os.path.exists(sub_file) and sub_file not in seen_paths:
                item_files.append(sub_file)
                seen_paths.add(sub_file)

        item_size = sum(os.path.getsize(f) for f in item_files)
        all_items.append((item_files, item_size))

    if not all_items: return

    batches, curr_batch, curr_size = [], [], 0
    for item_files, item_size in all_items:
        if curr_batch and (curr_size + item_size > PART_SIZE_LIMIT):
            batches.append(curr_batch)
            curr_batch, curr_size = [], 0
        curr_batch.extend(item_files)
        curr_size += item_size

    if curr_batch: batches.append(curr_batch)
    is_multi_part = len(batches) > 1

    for idx, batch in enumerate(batches, 1):
        part_folder_name = f"{clean_group_name}_part{idx:02d}" if is_multi_part else clean_group_name
        part_dir = os.path.join(base_dir, part_folder_name)
        os.makedirs(part_dir, exist_ok=True)

        for p in batch:
            dst = os.path.join(part_dir, os.path.basename(p))
            if p != dst and not os.path.exists(dst):
                shutil.move(p, dst)

        zip_name = f"{part_folder_name}.zip"
        batch_folder_size = sum(os.path.getsize(os.path.join(dp, f)) for dp, _, fn in os.walk(part_dir) for f in fn)

        orig = os.getcwd()
        os.chdir(base_dir)
        cmd = ["7z", "a", "-mx0", "-mmt=on"]
        if batch_folder_size > PART_SIZE_LIMIT:
            cmd.append("-v5000m")
        cmd.extend([zip_name, part_folder_name])

        subprocess.run(cmd, check=True)
        os.chdir(orig)
        shutil.rmtree(part_dir)

all_videos = natsorted([
    os.path.join(r, f) for r, _, files in os.walk(folder)
    for f in files if f.lower().endswith(video_ext)
])

series_regex = re.compile(r'(?i)(?:^(.*?)[.\s_-]+)?(?:S(\d{1,2})|\b(\d{1,2})x(\d{1,2})\b)')
series_groups = defaultdict(list)

for vid_path in all_videos:
    vid_name = os.path.basename(vid_path)
    match = series_regex.search(vid_name)
    if match:
        raw_title = match.group(1) or "Series"
        s_num = match.group(2) or match.group(3) or "01"
        series_groups[f"{raw_title.strip('. -_').lower()}_S{s_num}"].append(vid_path)

for group_key in natsorted(series_groups.keys()):
    vids = natsorted(series_groups[group_key])
    if len(vids) > 3:
        first_stem = os.path.splitext(os.path.basename(vids[0]))[0]
        create_7z_group(first_stem, vids, folder)
PYEOF

    echo "📤 Step 4: Parallel Uploads to Filemirage..."
    python3 - << 'PYEOF'
import os, subprocess, requests, time, fcntl
from concurrent.futures import ThreadPoolExecutor
from natsort import natsorted

FILEMIRAGE_API_TOKEN = '9QQH-DGES-CWQZ-FXNV'
FOLDER_PATH = 'downloads'

try:
    srv_res = requests.get("https://filemirage.com/api/servers", timeout=10).json()
    SERVER = srv_res['data']['server']
except Exception as e:
    print(f"Failed to fetch Filemirage server: {e}")
    exit(1)

def upload_single_file(file_path):
    filename = os.path.basename(file_path)
    file_size_mb = os.path.getsize(file_path) / (1024 * 1024)
    print(f"⬆️ [START] Uploading: {filename} ({file_size_mb:.2f} MB)", flush=True)
    
    curl_cmd = [
        "curl", "-X", "POST",
        f"{SERVER}/upload.php",
        "-H", f"Authorization: Bearer {FILEMIRAGE_API_TOKEN}",
        "-F", f'file=@"{file_path}"',
        "--max-time", "3600"
    ]
    
    proc = subprocess.Popen(curl_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    fd = proc.stderr.fileno()
    fl = fcntl.fcntl(fd, fcntl.F_GETFL)
    fcntl.fcntl(fd, fcntl.F_SETFL, fl | os.O_NONBLOCK)
    
    buffer = b""
    while proc.poll() is None:
        try:
            chunk = proc.stderr.read(1024)
            if chunk: buffer += chunk
        except Exception:
            pass
        time.sleep(0.5)
        
    stdout, stderr = proc.communicate()
    if proc.returncode == 0:
        print(f"✅ Uploaded {filename}: {stdout.decode('utf-8', errors='ignore').strip()}", flush=True)
    else:
        print(f"❌ Curl Error uploading {filename}: {stderr.decode('utf-8', errors='ignore').strip()}", flush=True)

if os.path.exists(FOLDER_PATH):
    upload_queue = natsorted([
        os.path.join(root, filename)
        for root, dirs, files in os.walk(FOLDER_PATH)
        for filename in files if not any(ext in filename for ext in [".!qB", ".part", ".aria2"])
    ])
    
    if upload_queue:
        print(f"🚀 Launching 4 parallel upload workers for {len(upload_queue)} files...", flush=True)
        with ThreadPoolExecutor(max_workers=4) as executor:
            executor.map(upload_single_file, upload_queue)
PYEOF

    echo "🎉 Processing & upload finished successfully!"
    EOF
  ]
}
