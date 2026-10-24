# Network Shield — DNS mã hoá & kiểm tra VPN

## Tính năng này làm gì

- Cài một **profile DNS-over-HTTPS toàn hệ thống**: mọi app, kể cả game, gửi truy vấn DNS qua HTTPS tới resolver đã chọn.
- **AdGuard DNS** và **NextDNS** lọc domain quảng cáo/tracker ngay tại resolver. Cloudflare và Quad9 không lọc tracker.
- **Không phải VPN**: không đổi IP, không đi qua tunnel, không can thiệp traffic của game. Nó chỉ mã hoá và (tuỳ resolver) lọc DNS.
- App có thêm **VPN gate**: kiểm tra interface `utun`/`ipsec`/`ppp`. Nếu bật *Require VPN before inject*, app sẽ không cho inject khi chưa có VPN/tunnel.

## Cài đặt

1. Mở **Setting → NETWORK SHIELD**.
2. Chọn **Resolver**:
   - **AdGuard DNS** — chặn quảng cáo/tracker sẵn, không cần tài khoản (dễ nhất).
   - **NextDNS** — tạo profile tại [nextdns.io](https://nextdns.io), copy **config ID** (6 ký tự hex), dán vào ô trong app.
   - **Cloudflare** / **Quad9** — nhanh và ổn định, không lọc tracker.
   - **Custom DoH** — endpoint HTTPS bất kỳ bạn kiểm soát.
3. Bấm **Install DNS profile** → Safari mở trang local → bấm **Allow**.
4. Bấm **Open Settings** trong app → **Profile Downloaded → Install** → nhập mật khẩu máy.
5. Quay lại app → bấm **I installed it** → bấm **Test resolver**. Kết quả `xxx ms` nghĩa là endpoint trả lời được.
6. Kiểm tra thực tế: mở Safari → [dnsleaktest.com](https://www.dnsleaktest.com). Resolver phải là nhà cung cấp bạn chọn, không phải ISP.
7. Mở game, đăng nhập và vào một trận thử. Nếu game không kết nối được, xoá profile và cài lại **không bật lọc tracker**.

> Mọi thứ khác — VPN gate, copy blocklist, leak test, cài lại — nằm trong **Advanced**.

## NextDNS denylist

- Trong app, chọn **NextDNS** → mở **Advanced** → bấm **Copy full blocklist**.
- Dán vào NextDNS dashboard → **Privacy → Denylist**.
- Danh sách gồm endpoint analytics/tracker (Firebase, AppsFlyer, Adjust, Amplitude, Mixpanel, Segment, Branch, Unity Ads, Google Analytics...) **và** các host security của Free Fire (xem mục dưới).
- **Tuyệt đối không chặn domain game, login, matchmaking hay thanh toán.** Chặn nhầm sẽ làm game mất kết nối hoặc không đăng nhập được.

## Chặn domain publisher / anti-cheat (NextDNS)

Mục tiêu: chặn các hostname báo cáo/security của Free Fire ở tầng DNS. Đây là phần gần nhất với "chặn quét hack của NPH" mà **không cần Network Extension**.

1. Trong app: **Resolver = NextDNS**, nhập config ID, cài profile (mục trên).
2. Mở **Advanced** → bấm **Copy full blocklist** (đã gồm cả 3 host dưới).
3. Mở **NextDNS dashboard** (nút trong Advanced) → **Privacy → Denylist**, dán list. Nếu muốn test từng cái, chỉ dán từng domain một:
   - `csoversea.stronghold.freefiremobile.com` — security/stronghold
   - `gamesecurity.sea.freefiremobile.com` — game security khu vực SEA
   - `adv.wfpj.freefiremobile.com` — quảng cáo
4. Nếu game crash hoặc không login: bỏ domain vừa thêm, thử lại.
5. **NextDNS → Logs** hiển thị domain game đang gọi. Chơi một trận rồi thêm các tên telemetry/report/security bạn thấy vào Denylist.

**Không chặn** các domain sau (mất kết nối/không vào trận):

- `gin.freefiremobile.com`, `na-gin.freefiremobile.com`
- `*.network.freefiremobile.com` (gateway theo khu vực)
- `dl.*.freefiremobile.com` (CDN tải game)

**Giới hạn thật:**

- DNS chỉ chặn **phân giải tên**. Anti-cheat quét trong process/bộ nhớ, dùng IP cứng, hoặc tự chạy DoH riêng thì DNS không thấy và không chặn được.
- Blocking security host có thể làm game crash/không login; luôn thêm từng cái và test.
- Không đảm bảo không ban; đây là giảm kênh báo cáo, không phải vô hiệu hoá anti-cheat.

## VPN (nếu cần đổi IP)

- DNS profile **không đổi IP**. Muốn đổi egress IP, dùng VPN thật (WireGuard, IKEv2, app VPN tin cậy).
- Bật **Require VPN before inject** nếu muốn app chặn inject khi chưa có tunnel.
- Kết nối VPN **trước khi mở game** và giữ nguyên quốc gia/IP trong suốt phiên. Đổi IP/quốc gia giữa phiên là tín hiệu rủi ro mạnh hơn nhiều so với một đường DNS sạch.
- DNS profile và VPN có thể dùng cùng lúc. Nhiều VPN tự đặt DNS riêng, nên kiểm tra lại bằng `dnsleaktest.com` sau khi bật VPN.

## Giới hạn & rủi ro

- **Không đảm bảo không bị ban.** Telemetry/anti-cheat phía server nằm ngoài tầm với của DNS và VPN. Đây là lớp vệ sinh mạng, không phải bảo hiểm tài khoản.
- Profile là **"Not Signed"** (tự tạo), iOS sẽ cảnh báo — bình thường, chỉ cần kiểm tra đúng tên profile.
- Đừng chặn domain game. Nếu nghi ngờ, gỡ profile và chơi lại một trận để xác nhận.
- Gỡ profile: **Settings → General → VPN & Device Management → Configuration Profile → Vortex Arena DNS Shield → Remove Profile**.

## Gỡ lỗi nhanh

| Hiện tượng | Cách xử lý |
| --- | --- |
| App hỏi quyền **Local Network** | Chọn **Allow**. App chỉ dùng loopback `127.0.0.1` để đưa profile sang Safari, không quét mạng LAN. |
| Safari không mở | Thử lại khi app đang foreground; đảm bảo dùng Safari, không phải browser trong app khác. |
| Không thấy "Profile Downloaded" | Kiểm tra đã bấm **Allow** ở banner tải profile; thử lại. |
| Test resolver fail | Kiểm tra ID/URL và mạng; thử Cloudflare để loại trừ resolver. |
| Tunnel "Not detected" dù VPN đang bật | Một số VPN không lộ interface qua proxy table; tắt **Require VPN** để không chặn inject. |
| Game không login/matchmaking | Gỡ profile, cài lại với Cloudflare (không lọc), rồi thêm denylist từng bước. |

## Ghi chú kỹ thuật

- Profile dùng payload `com.apple.dnsSettings.managed` (`DNSSettingsDNSProtocol = HTTPS`). Không cần Network Extension entitlement, nên chạy được trên bản unsigned/TrollStore.
- Profile được phục vụ qua một HTTP server loopback (`127.0.0.1`) và mở bằng Safari — iOS chỉ cài profile qua đường tải xuống, không cài từ `file://`.
- App xin background-task assertion trong lúc chuyển sang Safari để server không bị suspend trước khi profile tải xong.
- `Require VPN` chỉ là heuristic đọc bảng proxy scoped của CFNetwork; nó không chứng minh được traffic game đã đi qua VPN.
- DNS lọc không thấy được nội dung traffic, không chặn được endpoint dùng IP trực tiếp hoặc DoH riêng của game.
