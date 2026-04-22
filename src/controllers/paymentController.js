const stripe = require("../services/stripeService");
const pool = require("../config/db");
const crypto = require("crypto");

const db = pool.promise();

const ensureBookingPaymentColumns = async () => {
  const columnsToEnsure = [
    {
      name: "user_id",
      ddl: "ALTER TABLE bookings ADD COLUMN user_id INT NULL AFTER id"
    },
    {
      name: "amount",
      ddl: "ALTER TABLE bookings ADD COLUMN amount DECIMAL(10,2) NOT NULL DEFAULT 0 AFTER status"
    },
    {
      name: "currency",
      ddl: "ALTER TABLE bookings ADD COLUMN currency VARCHAR(10) NOT NULL DEFAULT 'try' AFTER amount"
    },
    {
      name: "stripe_session_id",
      ddl: "ALTER TABLE bookings ADD COLUMN stripe_session_id VARCHAR(255) DEFAULT NULL AFTER currency"
    },
    {
      name: "payment_status",
      ddl: "ALTER TABLE bookings ADD COLUMN payment_status ENUM('unpaid', 'paid', 'failed', 'refunded') NOT NULL DEFAULT 'unpaid' AFTER stripe_session_id"
    },
    {
      name: "updated_at",
      ddl: "ALTER TABLE bookings ADD COLUMN updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER created_at"
    },
    {
      name: "qr_token",
      ddl: "ALTER TABLE bookings ADD COLUMN qr_token VARCHAR(255) DEFAULT NULL AFTER payment_status"
    },
    {
      name: "checked_in",
      ddl: "ALTER TABLE bookings ADD COLUMN checked_in TINYINT(1) NOT NULL DEFAULT 0 AFTER qr_token"
    },
    {
      name: "checked_in_at",
      ddl: "ALTER TABLE bookings ADD COLUMN checked_in_at DATETIME DEFAULT NULL AFTER checked_in"
    }
  ];

  for (const column of columnsToEnsure) {
    const [rows] = await db.query(
      `
      SELECT COUNT(*) AS count
      FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'bookings'
        AND COLUMN_NAME = ?
      `,
      [column.name]
    );

    if (rows?.[0]?.count === 0) {
      await db.query(column.ddl);
    }
  }
};

const buildQrToken = () => crypto.randomUUID();

const markBookingAsPaidAndApproved = async (bookingId) => {
  const [rows] = await db.query(
    `
    SELECT id, event_id, ticket_count, status, payment_status, qr_token, checked_in
    FROM bookings
    WHERE id = ?
    LIMIT 1
    `,
    [bookingId]
  );

  if (!rows.length) {
    throw new Error("Booking not found for completed payment");
  }

  const booking = rows[0];

  if (booking.payment_status === "paid" && booking.status === "approved" && booking.qr_token) {
    return booking;
  }

  const [eventRows] = await db.query(
    "SELECT available_seats FROM events WHERE id = ? LIMIT 1",
    [booking.event_id]
  );

  if (!eventRows.length) {
    throw new Error("Event not found for completed payment");
  }

  if (booking.status !== "approved") {
    if (Number(eventRows[0].available_seats) < Number(booking.ticket_count)) {
      await db.query(
        `
        UPDATE bookings
        SET payment_status = 'paid', updated_at = NOW()
        WHERE id = ?
        `,
        [bookingId]
      );

      throw new Error("Payment completed but there are no seats left to approve this booking");
    }

    await db.query(
      "UPDATE events SET available_seats = available_seats - ? WHERE id = ?",
      [booking.ticket_count, booking.event_id]
    );
  }

  const qrToken = booking.qr_token || buildQrToken();

  await db.query(
    `
    UPDATE bookings
    SET status = 'approved',
        payment_status = 'paid',
        qr_token = ?,
        updated_at = NOW()
    WHERE id = ?
    `,
    [qrToken, bookingId]
  );

  return {
    ...booking,
    status: "approved",
    payment_status: "paid",
    qr_token: qrToken,
  };
};

const createCheckoutSession = async (req, res) => {
  try {
    const userId = req.user?.userId || req.user?.id;
    const { eventId, ticketCount } = req.body;
    const normalizedTicketCount = Number(ticketCount) || 1;

    if (!userId) {
      return res.status(401).json({
        message: "Authenticated user id not found in token",
      });
    }

    if (!eventId) {
      return res.status(400).json({
        message: "eventId is required",
      });
    }

    if (!Number.isInteger(normalizedTicketCount) || normalizedTicketCount <= 0) {
      return res.status(400).json({
        message: "ticketCount must be a positive integer",
      });
    }

    await ensureBookingPaymentColumns();

    // Event'i bul
    const [events] = await db.query(
      "SELECT * FROM events WHERE id = ? AND status = 'active'",
      [eventId]
    );

    if (events.length === 0) {
      return res.status(404).json({
        message: "Event not found or not active",
      });
    }

    const event = events[0];

    // Koltuk kontrolü
    if (Number(event.available_seats) < normalizedTicketCount) {
      return res.status(400).json({
        message: "Not enough seats available for this event",
      });
    }

    const totalAmount = (Number(event.price) || 0) * normalizedTicketCount;

    // Önce pending booking oluştur
    const [bookingResult] = await db.query(
      `
      INSERT INTO bookings (
        user_id,
        event_id,
        customer_name,
        customer_email,
        ticket_count,
        status,
        amount,
        currency,
        payment_status,
        created_at,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, 'pending', ?, 'try', 'unpaid', NOW(), NOW())
      `,
      [
        userId,
        eventId,
        req.user?.name || "Unknown User",
        req.user?.email || "unknown@example.com",
        normalizedTicketCount,
        totalAmount,
      ]
    );

    const bookingId = bookingResult.insertId;

    // Stripe Checkout Session oluştur
    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      payment_method_types: ["card"],
      line_items: [
        {
          price_data: {
            currency: "try",
            product_data: {
              name: event.title,
              description: event.description || "Event ticket",
            },
            unit_amount: Math.round((Number(event.price) || 0) * 100),
          },
          quantity: normalizedTicketCount,
        },
      ],
      success_url: `${process.env.CLIENT_URL}/payment-success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${process.env.CLIENT_URL}/payment-cancel`,
      metadata: {
        booking_id: bookingId.toString(),
        user_id: userId.toString(),
        event_id: eventId.toString(),
        ticket_count: normalizedTicketCount.toString(),
      },
    });

    // Session id'yi booking'e kaydet
    await db.query(
      `
      UPDATE bookings
      SET stripe_session_id = ?, updated_at = NOW()
      WHERE id = ?
      `,
      [session.id, bookingId]
    );

    return res.status(200).json({
      message: "Checkout session created successfully",
      data: {
        bookingId,
        sessionId: session.id,
        checkoutUrl: session.url,
      },
    });
  } catch (error) {
    console.error("createCheckoutSession error:", error);

    return res.status(500).json({
      message: "Failed to create checkout session",
      error: error.message,
    });
  }
};

const handleStripeWebhook = async (req, res) => {
  try {
    await ensureBookingPaymentColumns();

    const signature = req.headers["stripe-signature"];

    if (!signature) {
      return res.status(400).send("Missing Stripe signature");
    }

    if (!process.env.STRIPE_WEBHOOK_SECRET) {
      return res.status(500).send("STRIPE_WEBHOOK_SECRET is not configured");
    }

    const event = stripe.webhooks.constructEvent(
      req.body,
      signature,
      process.env.STRIPE_WEBHOOK_SECRET
    );

    if (event.type === "checkout.session.completed") {
      const session = event.data.object;
      const bookingId = Number(session.metadata?.booking_id || 0);

      if (bookingId > 0) {
        await markBookingAsPaidAndApproved(bookingId);
      }
    }

    if (event.type === "checkout.session.expired") {
      const session = event.data.object;
      const bookingId = Number(session.metadata?.booking_id || 0);

      if (bookingId > 0) {
        await db.query(
          `
          UPDATE bookings
          SET payment_status = 'failed', updated_at = NOW()
          WHERE id = ? AND payment_status = 'unpaid'
          `,
          [bookingId]
        );
      }
    }

    return res.json({ received: true });
  } catch (error) {
    console.error("handleStripeWebhook error:", error);
    return res.status(400).send(`Webhook Error: ${error.message}`);
  }
};

const finalizeCheckoutSession = async (req, res) => {
  try {
    await ensureBookingPaymentColumns();

    const sessionId = String(req.query?.session_id || "").trim();

    if (!sessionId) {
      return res.status(400).json({
        message: "session_id query param is required"
      });
    }

    const session = await stripe.checkout.sessions.retrieve(sessionId);

    if (!session) {
      return res.status(404).json({
        message: "Checkout session not found"
      });
    }

    if (session.payment_status !== "paid") {
      return res.status(409).json({
        message: "Payment is not completed yet",
        data: {
          sessionId: session.id,
          paymentStatus: session.payment_status || "unknown"
        }
      });
    }

    let bookingId = Number(session.metadata?.booking_id || 0);

    if (bookingId <= 0) {
      const [rows] = await db.query(
        `
        SELECT id
        FROM bookings
        WHERE stripe_session_id = ?
        ORDER BY id DESC
        LIMIT 1
        `,
        [session.id]
      );

      bookingId = rows?.[0]?.id || 0;
    }

    if (!Number.isInteger(bookingId) || bookingId <= 0) {
      return res.status(404).json({
        message: "Booking not found for this checkout session"
      });
    }

    const booking = await markBookingAsPaidAndApproved(bookingId);

    return res.status(200).json({
      message: "Checkout session finalized successfully",
      data: {
        bookingId,
        paymentStatus: "paid",
        bookingStatus: "approved",
        qrToken: booking.qr_token || null,
      }
    });
  } catch (error) {
    console.error("finalizeCheckoutSession error:", error);
    return res.status(500).json({
      message: "Failed to finalize checkout session",
      error: error.message
    });
  }
};

const syncMyPaidBookings = async (req, res) => {
  try {
    await ensureBookingPaymentColumns();

    const userEmail = req.user?.email;

    if (!userEmail) {
      return res.status(400).json({
        message: "User email not found in token"
      });
    }

    const [rows] = await db.query(
      `
      SELECT id, stripe_session_id
      FROM bookings
      WHERE customer_email = ?
        AND payment_status = 'unpaid'
        AND stripe_session_id IS NOT NULL
        AND stripe_session_id <> ''
      ORDER BY id DESC
      LIMIT 30
      `,
      [userEmail]
    );

    let checked = 0;
    let synced = 0;
    let failed = 0;

    for (const row of rows) {
      checked += 1;

      try {
        const session = await stripe.checkout.sessions.retrieve(row.stripe_session_id);

        if (session?.payment_status === "paid") {
          await markBookingAsPaidAndApproved(row.id);
          synced += 1;
        }
      } catch (error) {
        failed += 1;
        console.error("syncMyPaidBookings session check failed:", error.message);
      }
    }

    return res.status(200).json({
      message: "Payment sync completed",
      data: {
        checked,
        synced,
        failed,
      }
    });
  } catch (error) {
    console.error("syncMyPaidBookings error:", error);
    return res.status(500).json({
      message: "Failed to sync payments",
      error: error.message
    });
  }
};
const getMyQrTicket = async (req, res) => {
  try {
    await ensureBookingPaymentColumns();

    const bookingId = Number(req.params.bookingId);
    const userEmail = req.user?.email;
    const userRole = req.user?.role;

    if (!Number.isInteger(bookingId) || bookingId <= 0) {
      return res.status(400).json({ message: "Invalid booking id" });
    }

    if (!userEmail) {
      return res.status(400).json({ message: "User email not found in token" });
    }

    const [rows] = await db.query(
      `
      SELECT
        b.id,
        b.event_id,
        b.customer_name,
        b.customer_email,
        b.ticket_count,
        b.status,
        b.payment_status,
        b.qr_token,
        b.checked_in,
        b.checked_in_at,
        e.title,
        e.location,
        e.event_date
      FROM bookings b
      JOIN events e ON e.id = b.event_id
      WHERE b.id = ?
        AND (? = 'admin' OR b.customer_email = ?)
      LIMIT 1
      `,
      [bookingId, userRole || "user", userEmail]
    );

    if (!rows.length) {
      return res.status(404).json({ message: "Booking not found" });
    }

    const booking = rows[0];

    if (booking.payment_status !== "paid" || booking.status !== "approved") {
      return res.status(400).json({
        message: "QR ticket is available only for paid and approved bookings"
      });
    }

    if (!booking.qr_token) {
      const qrToken = buildQrToken();

      await db.query(
        `
        UPDATE bookings
        SET qr_token = ?, updated_at = NOW()
        WHERE id = ?
        `,
        [qrToken, bookingId]
      );

      booking.qr_token = qrToken;
    }

    return res.json({
      message: "QR ticket fetched successfully",
      data: booking
    });
  } catch (error) {
    console.error("getMyQrTicket error:", error);
    return res.status(500).json({
      message: "Failed to fetch QR ticket",
      error: error.message
    });
  }
};

const verifyQrTicket = async (req, res) => {
  try {
    await ensureBookingPaymentColumns();

    const qrToken = req.body?.qrToken;

    if (!qrToken) {
      return res.status(400).json({ message: "qrToken is required" });
    }

    const [rows] = await db.query(
      `
      SELECT
        b.id,
        b.event_id,
        b.customer_name,
        b.customer_email,
        b.ticket_count,
        b.status,
        b.payment_status,
        b.qr_token,
        b.checked_in,
        b.checked_in_at,
        e.title,
        e.location,
        e.event_date
      FROM bookings b
      JOIN events e ON e.id = b.event_id
      WHERE b.qr_token = ?
      LIMIT 1
      `,
      [qrToken]
    );

    if (!rows.length) {
      return res.status(404).json({ message: "QR ticket not found" });
    }

    const booking = rows[0];

    if (booking.payment_status !== "paid" || booking.status !== "approved") {
      return res.status(400).json({
        message: "This ticket is not eligible for check-in"
      });
    }

    if (Number(booking.checked_in) === 1) {
      return res.status(409).json({
        message: "This ticket has already been checked in",
        data: booking
      });
    }

    await db.query(
      `
      UPDATE bookings
      SET checked_in = 1,
          checked_in_at = NOW(),
          updated_at = NOW()
      WHERE id = ?
      `,
      [booking.id]
    );

    return res.json({
      message: "QR ticket verified successfully",
      data: {
        ...booking,
        checked_in: 1
      }
    });
  } catch (error) {
    console.error("verifyQrTicket error:", error);
    return res.status(500).json({
      message: "Failed to verify QR ticket",
      error: error.message
    });
  }
};

module.exports = {
  createCheckoutSession,
  handleStripeWebhook,
  finalizeCheckoutSession,
  syncMyPaidBookings,
  getMyQrTicket,
  verifyQrTicket,
};
