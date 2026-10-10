# Đưa ffxc-auth lên VPS — chạy 24/7 (tắt máy nhà vẫn online)

Máy ở nhà/quán không thể "luôn trực tuyến" khi bạn tắt nó. Muốn tắt máy mà auth vẫn chạy
thì phải đặt server trên **một máy chủ luôn bật (VPS)**. Code thì y như cũ — chỉ đổi chỗ chạy.

---

## 0. Chuẩn bị

- **1 VPS** Ubuntu 22.04/24.04, 1 GB RAM là đủ. Ví dụ: Vultr, DigitalOcean, Hetzner,
  Oracle Cloud (có gói free), Vietnix, AZDIGI, Tino…
- **1 tên miền / subdomain**, ví dụ `auth.tenmien.com`.
- **3 thứ phải mang theo** từ máy hiện tại (đừng để mất):
  - `keys/private.pem` — khoá ký license
  - `data/store.json` — danh sách key đã tạo
  - `.env` — token + cấu hình

> ⚠️ **Tuyệt đối KHÔNG chạy `npm run mint` lại trên VPS.** Đổi khoá là mọi key cũ và bản IPA
> đang dùng sẽ hỏng. Chỉ **copy nguyên `keys/private.pem` cũ** sang.

---

## Cách 1 — Docker + Caddy (khuyến nghị, tự HTTPS)

### 1. Trỏ DNS về VPS
Trong trang quản lý tên miền, thêm bản ghi **A**:

| Type | Name | Value |
|------|------|-------|
| A | `auth` (hoặc `@`) | `IP_VPS` |

Chờ 1–5 phút cho DNS cập nhật.

### 2. SSH vào VPS và cài Docker
```bash
ssh root@IP_VPS
curl -fsSL https://get.docker.com | sh
```
Hoặc dùng script có sẵn (sau khi đã copy code): `bash deploy/install-vps.sh`

### 3. Copy project lên VPS
Trên **Windows PowerShell** (không cần copy `node_modules`):
```powershell
cd C:\Users\Administrator\Downloads\van-an-ipa-main
Compress-Archive -Force -DestinationPath ffxc-auth.zip -Path `
  ffxc-auth\src, ffxc-auth\scripts, ffxc-auth\deploy, ffxc-auth\keys, ffxc-auth\data, `
  ffxc-auth\.env, ffxc-auth\.dockerignore, ffxc-auth\package.json, `
  ffxc-auth\package-lock.json, ffxc-auth\tsconfig.json
scp ffxc-auth.zip root@IP_VPS:/opt/
```
Trên VPS:
```bash
cd /opt && apt-get install -y unzip && unzip -o ffxc-auth.zip
```

### 4. Sửa `.env` trên VPS
```bash
cd /opt/ffxc-auth
nano .env
```
Đảm bảo có:
```
ADMIN_TOKEN=<giữ đúng token hiện tại>
DOMAIN=auth.tenmien.com
```
Giữ nguyên `PRODUCT_ID`, `PORT=8787`, `KEY_PREFIX=VT`… Đổi `DOMAIN` thành tên miền thật của bạn.

### 5. Chạy
```bash
cd /opt/ffxc-auth
docker compose -f deploy/docker-compose.yml up -d --build
docker compose -f deploy/docker-compose.yml ps
```

### 6. Kiểm tra
```bash
curl https://auth.tenmien.com/health
# {"ok":true,"product":"pkg_40921350d3307e51491f27cb"}
```
Mở console: `https://auth.tenmien.com/admin`

### 7. Mở firewall
Nếu VPS dùng ufw hoặc firewall của nhà cung cấp, mở **80** và **443** (Caddy cần 80 để cấp
và gia hạn chứng chỉ).

### 8. Trỏ app iOS sang host mới
Sửa endpoint trong app (`ProtocolConstants.endpoint` / chỗ cấu hình) thành:
```
https://auth.tenmien.com/api
```
rồi **rebuild IPA**. Từ giờ app dùng VPS, tắt máy nhà không ảnh hưởng gì.

---

## Cách 2 — systemd + Node (không Docker)

```bash
# 1) Node 20 + Caddy
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs caddy

# 2) Copy code vào /opt/ffxc-auth (như bước 3), rồi build
cd /opt/ffxc-auth
npm ci && npm run build

# 3) Tạo user chạy riêng + bật service (tự chạy lại khi crash/reboot)
useradd -r -s /usr/sbin/nologin ffxc 2>/dev/null || true
chown -R ffxc:ffxc /opt/ffxc-auth
cp deploy/ffxc-auth.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now ffxc-auth
systemctl status ffxc-auth

# 4) Caddy làm HTTPS
cp deploy/Caddyfile /etc/caddy/Caddyfile
#    -> TRONG /etc/caddy/Caddyfile đổi:  reverse_proxy auth:8787  ->  reverse_proxy 127.0.0.1:8787
#    -> đặt DOMAIN trong /etc/caddy/.env hoặc sửa thẳng tên miền trong file
systemctl reload caddy
```

---

## Vận hành thường ngày

| Việc | Lệnh |
|---|---|
| Xem log | `docker compose -f deploy/docker-compose.yml logs -f` |
| Cập nhật code | copy code mới lên → `docker compose -f deploy/docker-compose.yml up -d --build` |
| Khởi động lại | `docker compose -f deploy/docker-compose.yml restart` |
| Backup | chép `data/store.json` + `keys/private.pem` về máy (đây là **toàn bộ** dữ liệu) |

- `restart: unless-stopped` → container **tự bật lại khi VPS reboot hoặc app crash**.
- **Caddy tự gia hạn HTTPS** miễn phí.
- Store chỉ chạy được **1 tiến trình**: khi VPS đã chạy thì nên **tắt bản local** bằng
  `stop.cmd` (hoặc giữ local làm bản dự phòng LAN, nhưng store riêng, đừng trỏ chung).

---

## Nếu chưa có tên miền
iOS bắt buộc HTTPS. Không có tên miền thì:
- Dùng **Cloudflare Tunnel** trỏ về VPS (miễn phí, có HTTPS), hoặc
- Tạm dùng tên miền miễn phí (DuckDNS) rồi trỏ Caddy vào đó, hoặc
- Mua 1 domain rẻ (~50–200k/năm) — cách gọn nhất để Caddy tự cấp HTTPS.

---

## Giữ máy nhà chạy song song (tuỳ chọn)
Bộ watchdog đã cài ở máy hiện tại (`run-forever.cmd` + autostart) vẫn dùng tốt cho mạng LAN
nếu máy bật. Nhưng **nguồn chính thức nên là VPS**, vì chỉ VPS mới đảm bảo online khi bạn
tắt máy.
