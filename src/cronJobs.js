const cron = require("node-cron");
const db = require("./config/db");
const { sendExpiredEventEmail, sendReminderEmail } = require("./utils/mailer");

// HER 1 DAKİKADA ÇALIŞIR
cron.schedule("* * * * *", () => {
  console.log("⏰ Running cron job...");

  const selectSql = `
    SELECT * FROM events
    WHERE event_date < NOW() AND status = 'active'
  `;

  db.query(selectSql, async (selectErr, events) => {
    if (selectErr) {
      return console.error("Cron select error:", selectErr.message);
    }

    if (events.length === 0) {
      return console.log("ℹ️ No expired events found");
    }

    const updateSql = `
      UPDATE events
      SET status = 'inactive'
      WHERE event_date < NOW() AND status = 'active'
    `;

    db.query(updateSql, async (updateErr, result) => {
      if (updateErr) {
        return console.error("Cron update error:", updateErr.message);
      }

      console.log(`✅ ${result.affectedRows} event(s) updated to inactive`);

      for (const event of events) {
        try {
          await sendExpiredEventEmail(event);
          console.log(`📧 Email sent for event: ${event.title}`);
        } catch (mailErr) {
          console.error(`Mail error for event ${event.id}:`, mailErr.message);
        }
      }
    });
  });
});
// 🔔 REMINDER CRON (yarınki eventler)
cron.schedule("* * * * *", () => {
  console.log("🔔 Running reminder cron job...");

  const sql = `
    SELECT 
      bookings.id AS booking_id,
      bookings.customer_name,
      bookings.customer_email,
      bookings.ticket_count,
      bookings.reminder_sent,
      events.id AS event_id,
      events.title,
      events.location,
      events.event_date
    FROM bookings
    JOIN events ON bookings.event_id = events.id
    WHERE DATE(events.event_date) = DATE(DATE_ADD(NOW(), INTERVAL 1 DAY))
      AND bookings.reminder_sent = 0
  `;

  db.query(sql, async (err, results) => {
    if (err) {
      return console.error("Reminder cron error:", err.message);
    }

    if (results.length === 0) {
      return console.log("ℹ️ No reminders to send");
    }

    for (const row of results) {
      try {
        const booking = {
          customer_name: row.customer_name,
          customer_email: row.customer_email,
          ticket_count: row.ticket_count
        };

        const event = {
          id: row.event_id,
          title: row.title,
          location: row.location,
          event_date: row.event_date
        };

        await sendReminderEmail(booking, event);

        db.query(
          "UPDATE bookings SET reminder_sent = 1 WHERE id = ?",
          [row.booking_id]
        );

        console.log(`📧 Reminder sent to ${row.customer_email}`);
      } catch (mailErr) {
        console.error("Reminder mail error:", mailErr.message);
      }
    }
  });
});