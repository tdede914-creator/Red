# Payment Flow — KOBONG VPN BOT

Bot ini **polling-based**, tidak pakai webhook. Pattern ini persis seperti bot RDP milik user (`BOTRDP/src/utils/paymentTracker.js`).

## Kenapa polling, bukan webhook?

| Aspek | Webhook | Polling (yang dipakai bot ini) |
|-------|---------|-------------------------------|
| Butuh domain publik | ✅ Ya | ❌ Tidak |
| Butuh TLS cert | ✅ Ya | ❌ Tidak |
| Butuh reverse proxy | ✅ Ya | ❌ Tidak |
| Bisa di VPS behind NAT | ❌ Tidak | ✅ Ya |
| Konfigurasi tambahan di dashboard | ✅ Ya | ❌ Tidak |
| Real-time latency | Instan (< 1s) | Max 10s |
| Traffic overhead | Minimal | ~6 request/menit per order pending |

Untuk skala < ratusan pembayaran pending bersamaan, polling lebih simpel dan zero-config.

## Alur Lengkap

```
┌─────────┐    1. /start → 💰 Top Up → Rp 10.000 → QRIS
│ USER    │─────────────────────────────────────────────┐
└────┬────┘                                             │
     │                                                   ▼
     │                                        ┌──────────────────┐
     │                                        │ Bot Handler      │
     │                                        │ (payment.py)     │
     │                                        └──────┬───────────┘
     │                                               │ 2. Pakasir.create_payment()
     │                                               ▼
     │                                        ┌──────────────────┐
     │                                        │ Pakasir API      │
     │                                        │ /transactioncreate│
     │                                        └──────┬───────────┘
     │                                               │ 3. Response: payment_url, qr, etc
     │                                               ▼
     │       ┌────────────────────────────────────────┐
     │◀──────┤ Bot kirim link/QR + tombol "Bayar"    │
     │       │ + start PaymentPoller.track()          │
     │       └────────────────────────────────────────┘
     │                       │
     │ 4. User bayar QRIS    │ 5. Poller loop dimulai
     ▼                       ▼
┌─────────┐          ┌───────────────────┐
│ Bank/EW │          │ PaymentPoller     │
└────┬────┘          │ (payment_poller.py)│
     │               │                    │
     │ 6. Uang masuk │ Setiap 10 detik:   │
     │  ke Pakasir   │ ─▶ Pakasir.detail_ │
     └─────────────▶ │     payment()       │
                     └─────────┬──────────┘
                               │ 7. status == "completed"
                               ▼
                     ┌─────────────────────┐
                     │ Credit user balance │
                     │ Update order status │
                     │ Send Telegram notif │
                     └─────────┬───────────┘
                               │
                               ▼
                          ┌─────────┐
                          │ USER    │  ← 8. ✅ notif saldo bertambah
                          └─────────┘
```

## Implementasi Detail

### Buat transaksi baru (`bot/handlers/payment.py:pay_router`)

```python
async with Pakasir(settings.pakasir_slug, settings.pakasir_api_key) as pk:
    payment = await pk.create_payment(method, order_ref, amount)

# Persist ke DB
session.add(Order(order_ref=order_ref, status=PENDING, ...))

# Mulai polling background
poller.track(order_ref, amount, user.telegram_id)
```

### Polling loop (`bot/payment_poller.py:_poll_loop`)

```python
for attempt in range(MAX_RETRIES):   # 60 attempts
    detail = await pk.detail_payment(order_ref, amount)
    status = detail.status.lower()

    if status in {"completed", "success", "paid", "settlement"}:
        await self._on_success(...)   # credit user + notify
        return
    if status in {"canceled", "failed", "expired"}:
        await self._on_canceled(...)  # notify user
        return

    await asyncio.sleep(POLL_INTERVAL)  # 10s

await self._on_timeout(...)  # after 10 minutes
```

### Crash-safe

Kalau bot di-restart di tengah polling, `PaymentPoller.start()` akan resume otomatis:

```python
async def start(self):
    result = await session.execute(
        select(Order).where(Order.status == OrderStatus.PENDING)
    )
    for order in result.scalars():
        self.track(order.order_ref, order.amount, user.telegram_id)
```

### Idempotency

Baik poller maupun tombol "Cek Status" manual sama-sama update `Order.status = COMPLETED` dan credit balance. Yang duluan update wins — yang lain baca status non-PENDING dan skip. Tidak ada double-credit.

## Tuning Parameter

Di `bot/payment_poller.py`:

```python
class PaymentPoller:
    POLL_INTERVAL = 10  # detik antar-cek
    MAX_RETRIES = 60    # → 10 menit total window
```

Kalau mau lebih cepat detect (lebih boros API call):
```python
POLL_INTERVAL = 5
MAX_RETRIES = 120  # tetap 10 menit
```

Kalau mau kasih user lebih banyak waktu bayar:
```python
POLL_INTERVAL = 15
MAX_RETRIES = 80  # → 20 menit
```

## Rate Limit Pakasir

Kalau 100 order pending bersamaan × 6 req/min = 600 req/menit. Cek dengan Pakasir support kalau khawatir. Untuk skala kecil ini tidak masalah.
