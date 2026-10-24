# Hướng dẫn dùng Relay (bản dễ dùng)

Relay là cách chơi **không sửa code game**. Máy chỉ cài một chứng chỉ, traffic đi
qua server của bạn, và báo cáo anti-cheat bị sửa trên đường truyền. Game không
thấy method nào bị hook, không file lạ trong container.

---

## 0. Bạn cần gì

- Một VPS Ubuntu/Debian (1 GB RAM là đủ), có IP công khai.
- Một domain trỏ A record về IP đó — **nên có**, vì profile và dashboard sẽ chạy
  qua HTTPS. Không có domain thì dùng tạm `http://IP:8080`, nhưng iOS sẽ cảnh báo.
- Máy đã cài IPA Nimbus.

---

## 1. Đưa code lên VPS (1 lần)

Trên máy tính:

```bash
scp -r ffxc-auth root@<IP-VPS>:/opt/ffxc-auth
```

Trên VPS:

```bash
ssh root@<IP-VPS>
cd /opt/ffxc-auth
# ghi domain vào .env (nếu có)
echo "DOMAIN=game.tenmien.com" >> .env
bash deploy/install-relay.sh /opt/ffxc-auth
```

Script tự: cài Docker (nếu thiếu), thêm biến relay vào `.env`, mở cổng 1299,
build và chạy. Cuối script in ra đúng 4 URL cần dùng. Xong bước này là hết phần
server — **không sửa file JSON nào bằng tay**.

Kiểm tra nhanh: mở `https://<domain>/relay/` trên điện thoại, phải thấy dashboard.

---

## 2. Cài profile trên điện thoại (2 lần chạm + 1 công tắc)

1. Mở app Nimbus → **Setting** → mục **Relay**.
2. Dán `https://<domain>/relay` vào ô, bấm **Install**.
   Safari mở ra → **Allow** → thông báo *Profile Downloaded*.
3. **Settings → General → VPN & Device Management** → bấm profile → **Install**.
4. **Settings → General → About → Certificate Trust Settings** → bật công tắc
   cho *Nimbus Relay CA*.

Bước 4 là bắt buộc và **không app nào làm hộ được** (iOS chặn). Không bật thì
relay không đọc được gì cả.

---

## 3. Kiểm tra đường truyền

Trong app, mục **Relay**, bấm **Check**:

- `Relay OK — N capture(s)` → traffic đã về relay.
- `Relay unreachable: ...` → chưa vào được (xem bảng lỗi bên dưới).
- `Relay answered HTTP 404` → sai đường dẫn, nhớ hậu tố `/relay`.

Nếu dùng 4G (không phải Wi-Fi đã cấu hình proxy), cần bật tunnel IKEv2 — xem mục 6.

---

## 4. Chơi 1 trận rồi bấm Apply

1. Vào game, chơi **một trận bình thường** (chế độ capture, chưa sửa gì).
2. Mở `https://<domain>/relay/` → mục **Suggested rules**.
3. Relay đã chấm từng host/path và điền sẵn rule cho cái đáng sửa.
   Bấm **Apply** — rule sống ngay, **không cần restart**, không rớt trận.

Ứng viên tốt trông như: path có `report` / `check` / `verify` / `gin`, body có
`check_info` / `md5` / `signature`. Host quảng cáo, CDN, asset game sẽ **không**
xuất hiện trong danh sách — bộ chấm cố tình bảo thủ.

---

## 5. Bảng lỗi nhanh

| Hiện tượng | Nguyên nhân | Cách sửa |
|---|---|---|
| Check báo `unreachable` | Chưa vào được domain/port | `docker compose -f deploy/docker-compose.yml ps` phải thấy `relay` Up; mở `https://<domain>/relay/` trên máy tính |
| Game không vào được mạng sau khi cài profile | Cert chưa được trust | Làm lại bước 4 mục 2 |
| Game vào được nhưng dashboard trống | Traffic chưa qua relay | Đang dùng 4G mà chưa có tunnel, hoặc Wi-Fi khác mạng đã cấu hình |
| `upstream failed` trong capture | Host đó pinning cert | Bỏ host đó khỏi rule; relay báo lỗi chứ không im lặng |
| Apply xong không đổi gì | Rule không khớp path | Mở `/captures`, xem `applied` có tên rule không |

Xem log: `docker compose -f deploy/docker-compose.yml logs -f relay`

---

## 6. Chơi bằng 4G (tùy chọn)

Profile Wi-Fi chỉ áp proxy cho **một** mạng. Muốn đi 4G thì cần tunnel:

```bash
echo "RELAY_VPN_SERVER=<domain>"    >> .env
echo "RELAY_VPN_REMOTE_ID=<domain>" >> .env
echo "RELAY_VPN_USER=player"        >> .env
echo "RELAY_VPN_PASSWORD=<mat-khau>" >> .env
bash deploy/install-relay.sh /opt/ffxc-auth
```

Profile mới sẽ kèm payload IKEv2. Phía server cần strongSwan (container chưa có
trong repo) — nói nếu bạn muốn mình thêm.

---

## 7. Những gì KHÔNG tự động được

- **Công tắc trust certificate** — iOS bắt buộc người dùng bật.
- **Cert pinning** ở một host bất kỳ — host đó không MITM được; relay báo lỗi rõ.
- **Rewrite body nhị phân (protobuf)** — cần schema; hiện chỉ sửa JSON/text, còn
  protobuf thì capture lại dưới dạng `base64:` để phân tích sau.
- **File capture chứa token phiên** — đừng gửi cho ai. `data/` đã bị gitignore.
