const express = require("express");
const cors = require("cors");
require("dotenv").config();

if (process.env.DISABLE_CRON !== "true") {
  require("./cronJobs");
}

const db = require("./config/db");
const eventRoutes = require("./routes/eventRoutes");
const authRoutes = require("./routes/authRoutes");
const externalEventRoutes = require("./routes/externalEventRoutes");
const paymentRoutes = require("./routes/paymentRoutes");

const app = express();

app.use(cors());
app.use("/api/payments/webhook", express.raw({ type: "application/json" }));
app.use(express.json());
app.use("/external-events", externalEventRoutes);

app.get("/", (req, res) => {
  res.json({
    message: "Event Booking API is running"
  });
});

app.get("/payment-success", (req, res) => {
  const sessionId = req.query?.session_id || "";
  res.status(200).send(`
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Odeme Basarili</title>
        <style>
          body { font-family: Arial, sans-serif; padding: 24px; background: #f7f7f9; }
          .card { max-width: 560px; margin: 32px auto; background: #fff; border-radius: 12px; padding: 24px; box-shadow: 0 8px 24px rgba(0,0,0,0.08); }
          h1 { margin: 0 0 12px; color: #0f9d58; }
          p { line-height: 1.5; color: #333; }
          code { background: #f0f0f0; padding: 2px 6px; border-radius: 6px; }
          .status { margin-top: 12px; color: #555; }
          .actions { margin-top: 14px; }
          .btn {
            display: inline-block;
            padding: 10px 14px;
            border-radius: 10px;
            background: #4f46e5;
            color: #fff;
            text-decoration: none;
            font-weight: 600;
          }
        </style>
      </head>
      <body>
        <div class="card">
          <h1>Odeme basarili</h1>
          <p>Odemen tamamlandi. Uygulamaya geri donup <b>Rezervasyonlarim</b> ekranindan durumunu ve QR biletini kontrol edebilirsin.</p>
          ${sessionId ? `<p>Session: <code>${sessionId}</code></p>` : ""}
          <p id="status" class="status">Odeme kaydi dogrulaniyor...</p>
          <div class="actions">
            <a id="openAppBtn" class="btn" href="#">Uygulamaya Don</a>
          </div>
        </div>
        <script>
          (function () {
            const sessionId = ${JSON.stringify(sessionId)};
            const statusEl = document.getElementById('status');
            const openAppBtn = document.getElementById('openAppBtn');

            const openApp = () => {
              const query = sessionId ? ('?session_id=' + encodeURIComponent(sessionId)) : '';
              window.location.href = 'eventapp://payment-success' + query;
            };

            openAppBtn.addEventListener('click', function (e) {
              e.preventDefault();
              openApp();
            });

            if (!sessionId) {
              statusEl.textContent = 'Session bilgisi bulunamadi. Uygulamadan rezervasyonlarini yenile.';
              return;
            }

            fetch('/api/payments/finalize-session?session_id=' + encodeURIComponent(sessionId), {
              method: 'GET',
              headers: { 'Accept': 'application/json' }
            })
              .then(async (response) => {
                let body = null;
                try {
                  body = await response.json();
                } catch (_) {
                  body = null;
                }

                if (response.ok) {
                  statusEl.textContent = 'Rezervasyon odemesi dogrulandi. QR biletin hazir.';
                  setTimeout(openApp, 1100);
                  return;
                }

                const msg = body && body.message ? body.message : 'Odeme dogrulamasi tamamlanamadi.';
                statusEl.textContent = msg + ' Uygulamadan rezervasyonlarini yenileyebilirsin.';
              })
              .catch(() => {
                statusEl.textContent = 'Sunucuya ulasilamadi. Uygulamadan rezervasyonlarini yenile.';
              });
          })();
        </script>
      </body>
    </html>
  `);
});

app.get("/payment-cancel", (req, res) => {
  res.status(200).send(`
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Odeme Iptal</title>
        <style>
          body { font-family: Arial, sans-serif; padding: 24px; background: #f7f7f9; }
          .card { max-width: 560px; margin: 32px auto; background: #fff; border-radius: 12px; padding: 24px; box-shadow: 0 8px 24px rgba(0,0,0,0.08); }
          h1 { margin: 0 0 12px; color: #d93025; }
          p { line-height: 1.5; color: #333; }
        </style>
      </head>
      <body>
        <div class="card">
          <h1>Odeme iptal edildi</h1>
          <p>Islem tamamlanmadi. Uygulamaya geri donup tekrar deneyebilirsin.</p>
        </div>
      </body>
    </html>
  `);
});

app.use("/events", eventRoutes);
app.use("/auth", authRoutes);
app.use("/api/payments", paymentRoutes);

db.query("SELECT 1", (err) => {
  if (err) {
    console.error("Database connection failed:", err.message);
  } else {
    console.log("Database connected successfully!");
  }
});

module.exports = app;